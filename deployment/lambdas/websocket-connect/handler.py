import json
import os
import boto3
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Handle WebSocket connection establishment"""
    try:
        connection_id = event['requestContext']['connectionId']
        
        # Authentication handled by API Gateway via API key requirement
        auth_method = 'none'
        user_id = 'anonymous'
        
        print(f"WebSocket connection established: {connection_id}")
        
        # Store connection in DynamoDB with TTL
        connections_table = dynamodb.Table(os.environ.get('CONNECTIONS_TABLE_NAME', 'websocket_connections'))
        
        # Set TTL for 24 hours from now
        ttl = int((datetime.now().timestamp()) + 86400)
        
        connections_table.put_item(
            Item={
                'connection_id': connection_id,
                'user_id': user_id,
                'auth_method': auth_method,
                'connected_at': datetime.now().isoformat(),
                'last_activity': datetime.now().isoformat(),
                'ttl': ttl
            }
        )
        
        print(f"WebSocket connection established: {connection_id}, auth: {auth_method}, user: {user_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Connected successfully',
                'connectionId': connection_id,
                'authMethod': auth_method
            })
        }
        
    except Exception as e:
        print(f"Error handling WebSocket connection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Connection error',
                'message': str(e)
            })
        }