import json
import os
import boto3

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Handle WebSocket disconnection"""
    try:
        connection_id = event['requestContext']['connectionId']
        
        # Remove connection from DynamoDB
        connections_table = dynamodb.Table(os.environ.get('CONNECTIONS_TABLE_NAME', 'websocket_connections'))
        
        connections_table.delete_item(
            Key={'connection_id': connection_id}
        )
        
        print(f"WebSocket connection disconnected: {connection_id}")
        
        return {
            'statusCode': 200,
            'body': 'Disconnected'
        }
        
    except Exception as e:
        print(f"Error handling WebSocket disconnection: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Disconnection error: {str(e)}'
        }