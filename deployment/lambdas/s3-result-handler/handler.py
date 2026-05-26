import json
import os
import boto3
from urllib.parse import unquote_plus
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
apigateway = None  # Will be initialized when needed

def send_websocket_message(connection_id, message):
    """Send message to WebSocket connection"""
    global apigateway
    
    if not apigateway:
        # Initialize API Gateway client with WebSocket endpoint
        websocket_endpoint = os.environ.get('WEBSOCKET_API_ENDPOINT', '').replace('wss://', 'https://')
        if websocket_endpoint:
            apigateway = boto3.client('apigatewaymanagementapi', endpoint_url=websocket_endpoint)
    
    if not apigateway or not connection_id:
        print(f"Cannot send WebSocket message - missing apigateway or connection_id")
        return
    
    try:
        apigateway.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(message)
        )
        print(f"Sent WebSocket message to {connection_id}: {message.get('action', 'unknown')}")
    except apigateway.exceptions.GoneException:
        print(f"Connection {connection_id} is stale, ignoring")
    except Exception as e:
        print(f"Error sending WebSocket message: {str(e)}")

def process_error_notification(error_data):
    """Process error notification from Step Functions"""
    try:
        job_id = error_data.get('jobId')
        connection_id = error_data.get('connectionId')
        error_message = error_data.get('error', 'Processing failed')
        
        print(f"Processing error notification for job {job_id}")
        
        if connection_id:
            # Send error message via WebSocket
            message = {
                'action': 'error',
                'jobId': job_id,
                'status': 'error',
                'error': error_message,
                'message': 'IMPAINTING processing failed'
            }
            
            send_websocket_message(connection_id, message)
            print(f"Sent error notification for job {job_id}")
        else:
            print(f"No connection ID for error notification of job {job_id}")
            
    except Exception as e:
        print(f"Error processing error notification: {str(e)}")

def lambda_handler(event, context):
    """Handle S3 events and error notifications for result delivery"""
    try:
        # Process SQS records containing S3 events or error notifications
        for record in event['Records']:
            # Parse SQS message body
            if 'body' in record:
                sqs_body = json.loads(record['body'])
                
                # Check if this is an error notification from Step Functions
                if 'eventType' in sqs_body and sqs_body['eventType'] == 'error':
                    process_error_notification(sqs_body)
                # Handle S3 event from SQS
                elif 'Records' in sqs_body:
                    for s3_record in sqs_body['Records']:
                        if s3_record.get('eventSource') == 'aws:s3':
                            handle_s3_event(s3_record)
            else:
                # Direct S3 event (if not using SQS)
                if record.get('eventSource') == 'aws:s3':
                    handle_s3_event(record)
        
        return {
            'statusCode': 200,
            'body': 'S3 events processed successfully'
        }
        
    except Exception as e:
        print(f"Error processing S3 events: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Error processing S3 events: {str(e)}'
        }

def handle_s3_event(s3_record):
    """Process individual S3 event"""
    try:
        event_name = s3_record['eventName']
        bucket_name = s3_record['s3']['bucket']['name']
        object_key = unquote_plus(s3_record['s3']['object']['key'])
        
        print(f"Processing S3 event: {event_name} for {bucket_name}/{object_key}")
        
        # Only process PUT events (object creation)
        if not event_name.startswith('ObjectCreated'):
            print(f"Ignoring event {event_name}")
            return
        
        # Check if this is a result image (in results/ folder)
        if object_key.startswith('results/'):
            handle_result_image(bucket_name, object_key)
        else:
            print(f"Ignoring S3 object not in results/ folder: {object_key}")
            
    except Exception as e:
        print(f"Error processing S3 event: {str(e)}")

def handle_result_image(bucket_name, object_key):
    """Handle result image upload, notify client via WebSocket"""
    try:
        # Extract job ID from object key (format: results/{job_id}-{timestamp}.jpg)
        filename = object_key.split('/')[-1]
        if '-' in filename:
            parts = filename.rsplit('-', 1)
            job_id = parts[0] if len(parts) > 1 else None
        else:
            job_id = None
        
        if not job_id:
            print(f"Could not extract job ID from {object_key}")
            return
        
        print(f"Processing result image for job {job_id}")
        
        # Get job details from DynamoDB
        jobs_table = dynamodb.Table(os.environ.get('JOBS_TABLE_NAME', os.environ.get('TABLE_NAME')))
        response = jobs_table.get_item(Key={'id': job_id})
        
        if 'Item' not in response:
            print(f"Job {job_id} not found in database")
            return
        
        job_item = response['Item']
        connection_id = job_item.get('connection_id')
        
        if not connection_id:
            print(f"No connection ID found for job {job_id}")
            return
        
        # Generate presigned URL for result image (24 hours expiration)
        presigned_url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket_name, 'Key': object_key},
            ExpiresIn=86400
        )
        
        # Update job status in DynamoDB with result URL
        from datetime import datetime
        jobs_table.update_item(
            Key={'id': job_id},
            UpdateExpression="SET result_s3_url = :result_url, updated_at = :updated_at",
            ExpressionAttributeValues={
                ":result_url": presigned_url,
                ":updated_at": datetime.now().isoformat()
            }
        )
        
        # Send WebSocket notification
        message = {
            "action": "result",
            "jobId": job_id,
            "resultUrl": presigned_url,
            "message": "Try-on ready for viewing"
        }
        
        send_websocket_message(connection_id, message)
        print(f"Sent result notification for job {job_id}")
        
    except Exception as e:
        print(f"Error handling result image {object_key}: {str(e)}")

