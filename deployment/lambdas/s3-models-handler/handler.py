import json
import os
import boto3
from urllib.parse import unquote_plus
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Handle S3 events for model catalog population"""
    try:
        # Process SQS records containing S3 events
        for record in event['Records']:
            # Parse SQS message body
            if 'body' in record:
                sqs_body = json.loads(record['body'])
                
                # Handle S3 event from SQS
                if 'Records' in sqs_body:
                    for s3_record in sqs_body['Records']:
                        if s3_record.get('eventSource') == 'aws:s3':
                            process_model_upload(s3_record)
            else:
                # Direct S3 event (if not using SQS)
                if record.get('eventSource') == 'aws:s3':
                    process_model_upload(record)
        
        return {
            'statusCode': 200,
            'body': 'Model uploads processed successfully'
        }
        
    except Exception as e:
        print(f"Error processing model uploads: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Error processing model uploads: {str(e)}'
        }

def process_model_upload(s3_record):
    """Process individual model upload"""
    try:
        event_name = s3_record['eventName']
        bucket_name = s3_record['s3']['bucket']['name']
        object_key = unquote_plus(s3_record['s3']['object']['key'])
        
        print(f"Processing model upload: {event_name} for {bucket_name}/{object_key}")
        
        # Only process PUT events (object creation)
        if not event_name.startswith('ObjectCreated'):
            print(f"Ignoring event {event_name}")
            return
        
        # Check if this is a model upload (in models/ folder)
        if not object_key.startswith('models/'):
            print(f"Ignoring S3 object not in models/ folder: {object_key}")
            return
            
        # Skip folder creation events (keys ending with /)
        if object_key.endswith('/'):
            print(f"Ignoring folder creation event: {object_key}")
            return
            
        # Only process image files
        valid_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp']
        if not any(object_key.lower().endswith(ext) for ext in valid_extensions):
            print(f"Ignoring non-image file: {object_key}")
            return
            
        handle_model_upload(bucket_name, object_key)
            
    except Exception as e:
        print(f"Error processing S3 event: {str(e)}")

def handle_model_upload(bucket_name, object_key):
    """Handle model image upload - auto-create model record"""
    try:
        print(f"Processing model upload: {object_key}")
        
        # Extract model info from object key
        # Flexible format: models/{model_name}.jpg OR models/{category}/{model_name}.jpg
        path_parts = object_key.split('/')
        if len(path_parts) < 2:
            print(f"Invalid model path format: {object_key}")
            return
        
        filename = path_parts[-1]
        model_name = filename.rsplit('.', 1)[0]  # Remove extension
        
        # Determine category and model ID based on path structure
        if len(path_parts) == 2:
            # Direct upload: models/model_name.jpg
            category = "general"
            model_id = model_name.lower().replace(' ', '-')
        else:
            # Category upload: models/category/model_name.jpg
            category = path_parts[1]
            model_id = f"{category}-{model_name}".lower().replace(' ', '-')
        
        # Create S3 URL
        s3_url = f"s3://{bucket_name}/{object_key}"
        
        # Check if model already exists
        models_table = dynamodb.Table(os.environ.get('MODELS_TABLE_NAME', 'models'))
        
        try:
            response = models_table.get_item(Key={'model_id': model_id})
            if 'Item' in response:
                print(f"Model {model_id} already exists, updating S3 URL")
                # Update existing model with new S3 URL
                models_table.update_item(
                    Key={'model_id': model_id},
                    UpdateExpression="SET model_picture_s3_url = :url, updated_at = :updated",
                    ExpressionAttributeValues={
                        ':url': s3_url,
                        ':updated': datetime.now().isoformat()
                    }
                )
                print(f"Updated model {model_id} with new S3 URL")
                return
        except Exception as e:
            print(f"Error checking existing model: {str(e)}")
        
        # Create new model record
        item = {
            'model_id': model_id,
            'model_picture_s3_url': s3_url,
            'name': model_name.replace('-', ' ').replace('_', ' ').title(),
            'category': category,
            'description': f"Auto-imported {category} model" if category != "general" else "Auto-imported model",
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'auto_imported': True
        }
        
        models_table.put_item(Item=item)
        print(f"Created model record: {model_id}")
        
    except Exception as e:
        print(f"Error handling model upload {object_key}: {str(e)}")