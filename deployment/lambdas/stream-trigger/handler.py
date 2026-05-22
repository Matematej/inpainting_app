import json
import boto3
import os
import time

def lambda_handler(event, context):
    """DynamoDB Stream trigger to start Step Functions for VTO jobs"""
    print(f'DynamoDB Stream event: {json.dumps(event, default=str)}')
    stepfunctions = boto3.client('stepfunctions')
    
    for record in event['Records']:
        print(f'Processing record: {record["eventName"]}')
        if record['eventName'] in ['INSERT', 'MODIFY']:
            # Extract job ID from DynamoDB record
            job_id = record['dynamodb']['Keys']['id']['S']
            print(f'Job ID: {job_id}')
            
            # Check if this is a new job creation (has status 'created')
            if 'NewImage' in record['dynamodb']:
                new_image = record['dynamodb']['NewImage']
                print(f'New image: {new_image}')
                if 'status' in new_image and new_image['status']['S'] == 'created':
                    print(f'Starting Step Functions for job {job_id}')
                    # Start Step Functions execution
                    try:
                        step_functions_input = {
                            'jobId': job_id,
                            'modelImageS3Url': new_image.get('model_picture_s3_url', {}).get('S', ''),
                            'productImageS3Url': new_image.get('product_picture_s3_url', {}).get('S', ''),
                            'connectionId': new_image.get('connection_id', {}).get('S', '')
                        }
                        print(f'Step Functions input: {json.dumps(step_functions_input)}')
                        
                        response = stepfunctions.start_execution(
                            stateMachineArn=os.environ['STATE_MACHINE_ARN'],
                            name=f'vto-job-{job_id}-{int(time.time())}',
                            input=json.dumps(step_functions_input)
                        )
                        print(f'Step Functions started: {response["executionArn"]}')
                    except Exception as e:
                        print(f'Error starting Step Functions: {str(e)}')
                        raise
                else:
                    print(f'Job {job_id} status is not "created", skipping')
    
    return {'statusCode': 200}