How to test:
1) upload sample images from /assets folder to S3 - moje_mistnost_test to models and zidle_test to products

2) Connect with WebSocket in terminal: npx wscat -c "wss://kyi9zyw7mj.execute-api.us-east-1.amazonaws.com/prod" -H "x-api-key: syz4qOFyBaHxYC1005Yq2kq0mvl3jX79oVQBxqr3"

3) Create job: {"action": "create_job", "model_id": "moje_mistnost_test", "product_id": "zidle_test", "parameters": {"prompt": "put the chair inside of the room"}}