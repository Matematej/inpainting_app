# How to Test

## 1. Deploy Terraform

Deploy Terraform from:

```
/deployment/terraform
```

---

## 2. Upload Sample Images to S3

Upload sample images from the `/assets` folder:

- `moje_mistnost_test.png` → upload to `models` folder
- `zidle_test.png` → upload to `products` folder

---

## 3. Connect to WebSocket

Run in terminal:

```bash
npx wscat -c "<outputs.websocket_api_endpoint>" -H "x-api-key: <API_KEY>"
```

Example:

```bash
npx wscat -c "wss://cyvwbxdp3a.execute-api.us-east-1.amazonaws.com/prod" -H "x-api-key: <API_KEY>"
```

---

## 4. Create a Job

Send the following message over the connection:

```json
{
  "action": "create_job",
  "model_id": "moje_mistnost_test",
  "product_id": "zidle_test",
  "parameters": {
    "prompt": "put the chair inside of the room"
  }
}
```