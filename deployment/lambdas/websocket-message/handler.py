import json
import os
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
apigateway = boto3.client('apigatewaymanagementapi', 
                         endpoint_url=os.environ.get('WEBSOCKET_API_ENDPOINT', '').replace('wss://', 'https://'))

def lambda_handler(event, context):
    """Handle WebSocket message routing"""
    try:
        connection_id = event['requestContext']['connectionId']
        
        # Parse incoming message
        body = json.loads(event.get('body', '{}'))
        action = body.get('action')
        
        print(f"Received WebSocket message from {connection_id}: {action}")
        
        # Handle different message types
        if action == 'create_job':
            # Create a new VTO job
            try:
                # Extract required parameters
                model_id = body.get('model_id')
                product_id = body.get('product_id')
                parameters = body.get('parameters', {})
                
                if not model_id or not product_id:
                    response_message = {
                        'action': 'error',
                        'error': 'Missing required parameters: model_id and product_id'
                    }
                else:
                    # Look up model and product in their respective DynamoDB tables
                    models_table = dynamodb.Table(os.environ.get('MODELS_TABLE_NAME', 'vto-models'))
                    products_table = dynamodb.Table(os.environ.get('PRODUCTS_TABLE_NAME', 'vto-products'))
                    
                    model_picture_s3_url = None
                    product_picture_s3_url = None
                    missing = []
                    
                    # Look up model in models table
                    try:
                        model_response = models_table.get_item(Key={'model_id': model_id})
                        if 'Item' in model_response:
                            model_picture_s3_url = model_response['Item'].get('model_picture_s3_url')
                        else:
                            missing.append(f"model '{model_id}'")
                    except Exception as e:
                        print(f"Error looking up model {model_id}: {str(e)}")
                        missing.append(f"model '{model_id}'")
                    
                    # Look up product in products table
                    try:
                        product_response = products_table.get_item(Key={'product_id': product_id})
                        if 'Item' in product_response:
                            product_picture_s3_url = product_response['Item'].get('product_picture_s3_url')
                        else:
                            missing.append(f"product '{product_id}'")
                    except Exception as e:
                        print(f"Error looking up product {product_id}: {str(e)}")
                        missing.append(f"product '{product_id}'")
                    
                    # Check if both were found
                    if missing:
                        response_message = {
                            'action': 'error',
                            'error': f'Not found in database: {" and ".join(missing)}'
                        }
                    else:
                        # Both found, proceed with job creation
                        try:
                            # Generate unique job ID
                            job_id = str(uuid.uuid4())
                            
                            # Create job record in DynamoDB
                            jobs_table = dynamodb.Table(os.environ.get('TABLE_NAME', 'virtual_try_on_jobs'))
                            
                            job_item = {
                                'id': job_id,
                                'model_id': model_id,
                                'product_id': product_id,
                                'model_picture_s3_url': model_picture_s3_url,
                                'product_picture_s3_url': product_picture_s3_url,
                                'parameters': parameters,
                                'connection_id': connection_id,
                                'status': 'created',
                                'created_at': datetime.now().isoformat()
                            }
                            
                            jobs_table.put_item(Item=job_item)
                            
                            response_message = {
                                'action': 'job_created',
                                'jobId': job_id,
                                'status': 'created',
                                'message': 'VTO job created successfully. Processing will begin shortly.'
                            }
                            
                            print(f"Created VTO job {job_id} for connection {connection_id}")
                            
                        except Exception as e:
                            response_message = {
                                'action': 'error',
                                'error': f'Error creating job: {str(e)}'
                            }
                    
            except Exception as e:
                print(f"Error creating job: {str(e)}")
                response_message = {
                    'action': 'error',
                    'error': f'Failed to create job: {str(e)}'
                }
                
        elif action == 'get_products':
            # Get available products from catalog
            try:
                products_table = dynamodb.Table(os.environ.get('PRODUCTS_TABLE_NAME', 'vto-products'))
                
                # Scan products table (in production, consider pagination)
                products_response = products_table.scan()
                products = products_response.get('Items', [])
                
                response_message = {
                    'action': 'products_list',
                    'products': products,
                    'count': len(products)
                }
                
            except Exception as e:
                print(f"Error getting products: {str(e)}")
                response_message = {
                    'action': 'error',
                    'error': f'Failed to get products: {str(e)}'
                }
                
        elif action == 'ping':
            # Simple ping/pong for connection health
            response_message = {
                'action': 'pong',
                'timestamp': datetime.now().isoformat()
            }
            
        elif action == 'subscribe':
            # Subscribe to job updates
            job_id = body.get('jobId')
            if job_id:
                # Store subscription in DynamoDB
                subscriptions_table = dynamodb.Table(os.environ.get('SUBSCRIPTIONS_TABLE_NAME', 'job_subscriptions'))
                subscriptions_table.put_item(
                    Item={
                        'job_id': job_id,
                        'connection_id': connection_id,
                        'subscribed_at': datetime.now().isoformat(),
                        'ttl': int(datetime.now().timestamp() + 86400)  # 24 hour TTL
                    }
                )
                
                response_message = {
                    'action': 'subscribed',
                    'jobId': job_id,
                    'message': f'Subscribed to job {job_id} updates'
                }
            else:
                response_message = {
                    'action': 'error',
                    'error': 'Missing jobId for subscription'
                }
                
        elif action == 'unsubscribe':
            # Unsubscribe from job updates
            job_id = body.get('jobId')
            if job_id:
                subscriptions_table = dynamodb.Table(os.environ.get('SUBSCRIPTIONS_TABLE_NAME', 'job_subscriptions'))
                subscriptions_table.delete_item(
                    Key={
                        'job_id': job_id,
                        'connection_id': connection_id
                    }
                )
                
                response_message = {
                    'action': 'unsubscribed',
                    'jobId': job_id,
                    'message': f'Unsubscribed from job {job_id} updates'
                }
            else:
                response_message = {
                    'action': 'error',
                    'error': 'Missing jobId for unsubscription'
                }
                
        else:
            response_message = {
                'action': 'error',
                'error': f'Unknown action: {action}'
            }
        
        # Send response back to client
        try:
            apigateway.post_to_connection(
                ConnectionId=connection_id,
                Data=json.dumps(response_message)
            )
            print(f"Sent response to {connection_id}: {response_message.get('action')}")
            
        except apigateway.exceptions.GoneException:
            # Connection is stale, clean it up
            print(f"Connection {connection_id} is gone, cleaning up")
            cleanup_stale_connection(connection_id)
            
        except Exception as e:
            print(f"Error sending message to {connection_id}: {str(e)}")
        
        return {
            'statusCode': 200,
            'body': 'Message processed'
        }
        
    except Exception as e:
        print(f"Error processing WebSocket message: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Message processing error: {str(e)}'
        }

def cleanup_stale_connection(connection_id):
    """Clean up stale connection from all tables"""
    try:
        # Remove from connections table
        connections_table = dynamodb.Table(os.environ.get('CONNECTIONS_TABLE_NAME', 'websocket_connections'))
        connections_table.delete_item(Key={'connection_id': connection_id})
        
        # Remove from subscriptions table
        subscriptions_table = dynamodb.Table(os.environ.get('SUBSCRIPTIONS_TABLE_NAME', 'job_subscriptions'))
        
        # Query all subscriptions for this connection
        response = subscriptions_table.scan(
            FilterExpression='connection_id = :conn_id',
            ExpressionAttributeValues={':conn_id': connection_id}
        )
        
        # Delete each subscription
        for item in response.get('Items', []):
            subscriptions_table.delete_item(
                Key={
                    'job_id': item['job_id'],
                    'connection_id': connection_id
                }
            )
            
        print(f"Cleaned up stale connection: {connection_id}")
        
    except Exception as e:
        print(f"Error cleaning up connection {connection_id}: {str(e)}")