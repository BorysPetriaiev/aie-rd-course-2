import json
import os
import boto3
import pypdf
import io

s3 = boto3.client("s3")


def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])

        if "Event" in body and body["Event"] == "s3:TestEvent":
            print("Skipping S3 test event")
            continue

        for s3_record in body.get("Records", []):
            bucket = s3_record["s3"]["bucket"]["name"]
            key = s3_record["s3"]["object"]["key"]

            if not key.startswith("uploads/") or not key.lower().endswith(".pdf"):
                print(f"Skipping non-PDF or non-upload file: {key}")
                continue

            print(f"Processing s3://{bucket}/{key}")

            response = s3.get_object(Bucket=bucket, Key=key)
            pdf_bytes = response["Body"].read()

            reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))
            pages_text = []
            for i, page in enumerate(reader.pages):
                text = page.extract_text() or ""
                pages_text.append(f"--- Page {i + 1} ---\n{text}")

            full_text = "\n\n".join(pages_text)

            filename = os.path.basename(key)
            stem = os.path.splitext(filename)[0]
            output_key = f"extracted/{stem}.txt"

            s3.put_object(
                Bucket=bucket,
                Key=output_key,
                Body=full_text.encode("utf-8"),
                ContentType="text/plain",
            )
            print(f"Saved extracted text to s3://{bucket}/{output_key}")

    return {"statusCode": 200, "body": "Done"}
