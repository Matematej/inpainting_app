import json
import os
import boto3
from urllib.parse import unquote_plus
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Handle S3 events for product catalog population"""
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
                            process_product_upload(s3_record)
            else:
                # Direct S3 event (if not using SQS)
                if record.get('eventSource') == 'aws:s3':
                    process_product_upload(record)
        
        return {
            'statusCode': 200,
            'body': 'Product uploads processed successfully'
        }
        
    except Exception as e:
        print(f"Error processing product uploads: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Error processing product uploads: {str(e)}'
        }

def process_product_upload(s3_record):
    """Process individual product upload"""
    try:
        event_name = s3_record['eventName']
        bucket_name = s3_record['s3']['bucket']['name']
        object_key = unquote_plus(s3_record['s3']['object']['key'])
        
        print(f"Processing product upload: {event_name} for {bucket_name}/{object_key}")
        
        # Only process PUT events (object creation)
        if not event_name.startswith('ObjectCreated'):
            print(f"Ignoring event {event_name}")
            return
        
        # Check if this is a product upload (in products/ folder)
        if not object_key.startswith('products/'):
            print(f"Ignoring S3 object not in products/ folder: {object_key}")
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
            
        handle_product_upload(bucket_name, object_key)
            
    except Exception as e:
        print(f"Error processing S3 event: {str(e)}")

def handle_product_upload(bucket_name, object_key):
    """Handle product image upload - auto-create product record"""
    try:
        print(f"Processing product upload: {object_key}")
        
        path_parts = object_key.split('/')
        if len(path_parts) < 2:
            print(f"Invalid product path format: {object_key}")
            return
        
        filename = path_parts[-1]
        product_name = filename.rsplit('.', 1)[0]  # Remove extension
        
        if len(path_parts) == 2:
            category = "general"
            product_id = product_name.lower().replace(' ', '-')
        else:
            category = path_parts[1]
            product_id = f"{category}-{product_name}".lower().replace(' ', '-')
        
        s3_url = f"s3://{bucket_name}/{object_key}"
        
        products_table = dynamodb.Table(os.environ.get('PRODUCTS_TABLE_NAME', 'products'))
        
        try:
            response = products_table.get_item(Key={'product_id': product_id})
            if 'Item' in response:
                print(f"Product {product_id} already exists, updating S3 URL")
                # Update existing product with new S3 URL
                products_table.update_item(
                    Key={'product_id': product_id},
                    UpdateExpression="SET product_picture_s3_url = :url, updated_at = :updated",
                    ExpressionAttributeValues={
                        ':url': s3_url,
                        ':updated': datetime.now().isoformat()
                    }
                )
                print(f"Updated product {product_id} with new S3 URL")
                return
        except Exception as e:
            print(f"Error checking existing product: {str(e)}")
        
        item = {
            'product_id': product_id,
            'product_picture_s3_url': s3_url,
            'name': product_name.replace('-', ' ').replace('_', ' ').title(),
            'category': category,
            'description': f"Auto-imported {category} product" if category != "general" else "Auto-imported product",
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'auto_imported': True
        }
        
        products_table.put_item(Item=item)
        print(f"Created product record: {product_id}")
        
    except Exception as e:
        print(f"Error handling product upload {object_key}: {str(e)}")