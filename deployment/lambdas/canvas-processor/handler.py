import json
import os
import boto3
import base64
import logging
from datetime import datetime
from random import randint
from decimal import Decimal

s3 = boto3.client('s3')
bedrock = boto3.client('bedrock-runtime', region_name='us-east-1')
dynamodb = boto3.resource('dynamodb')

logging.basicConfig(format="[%(levelname)s] %(message)s", level=logging.INFO)

MODEL_ID = "us.stability.stable-image-inpaint-v1:0"


def get_s3_image_b64(bucket_name, s3_url):
    if s3_url.startswith('s3://'):
        key = s3_url.replace('s3://', '').split('/', 1)[1]
    else:
        key = s3_url
    print(f"Fetching S3 key: {key}")
    resp = s3.get_object(Bucket=bucket_name, Key=key)
    return base64.b64encode(resp['Body'].read()).decode('utf-8')


def process_job(job_data):
    job_id       = job_data['id']
    bucket_name  = os.environ['BUCKET_NAME']
    parameters   = job_data.get('parameters', {})

    scene_url = job_data.get('model_picture_s3_url')
    mask_url  = job_data.get('product_picture_s3_url')

    if not scene_url:
        raise Exception("Missing model_picture_s3_url (room/scene photo)")

    prompt = parameters.get('prompt', 'a modern sofa')
    if isinstance(prompt, str) is False:
        prompt = str(prompt)

    print(f"Job {job_id}: prompt='{prompt}'")

    scene_b64 = get_s3_image_b64(bucket_name, scene_url)

    # StabilityAI inpaint request
    # Docs: https://platform.stability.ai/docs/api-reference#tag/Edit/paths/~1v2beta~1stable-image~1edit~1inpaint/post
    request_body = {
        "prompt": prompt,
        "image": scene_b64,
        "output_format": "jpeg",
        "seed": int(parameters.get('seed', randint(0, 4294967294))),
    }

    if parameters.get('negativePrompt'):
        request_body['negative_prompt'] = parameters['negativePrompt']

    if mask_url:
        print("Using provided mask image")
        request_body['mask'] = get_s3_image_b64(bucket_name, mask_url)
        grow = parameters.get('growMaskAmount', 5)
        if isinstance(grow, Decimal):
            grow = int(grow)
        request_body['grow_mask'] = grow

    print(f"Calling Bedrock model: {MODEL_ID}")
    response = bedrock.invoke_model(
        modelId=MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(request_body)
    )

    response_body = json.loads(response['body'].read().decode('utf-8'))

    images = response_body.get('images', [])
    if not images:
        raise Exception(f"No images in Stability response: {response_body}")

    result_b64 = images[0]

    # Save result to S3
    result_key = f"results/{job_id}-{int(datetime.now().timestamp())}.jpg"
    s3.put_object(
        Bucket=bucket_name,
        Key=result_key,
        Body=base64.b64decode(result_b64),
        ContentType='image/jpeg'
    )

    print(f"Result saved: {result_key}")
    return {
        'success': True,
        'result_s3_key': result_key,
        'message': 'Image generation completed successfully'
    }


def lambda_handler(event, context):
    """Entry point — called by Step Functions."""
    print(f"Canvas processor invoked: {json.dumps(event, default=str)}")

    job_id = event.get('jobId')
    if not job_id:
        raise Exception(f"No jobId in Step Functions input: {event}")

    table = dynamodb.Table(os.environ['TABLE_NAME'])
    resp = table.get_item(Key={'id': job_id})
    if 'Item' not in resp:
        raise Exception(f"Job {job_id} not found in DynamoDB")

    job_data = resp['Item']
    print(f"Processing job: {json.dumps(job_data, default=str)}")

    result = process_job(job_data)

    print(f"Job {job_id} completed successfully")
    return {
        'statusCode': 200,
        'jobId': job_id,
        'success': True,
        'result': result,
        'message': 'Canvas processing completed successfully'
    }
