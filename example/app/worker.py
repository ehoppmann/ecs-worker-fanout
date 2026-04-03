import json
import os
import time
import logging

import boto3


logfmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)
_ch = logging.StreamHandler()
_ch.setFormatter(logging.Formatter(logfmt))
_rootlogger = logging.getLogger()
_rootlogger.setLevel(logging.INFO)
_rootlogger.addHandler(_ch)


def main():
    sqs = boto3.client('sqs')
    queue_url = os.environ['SQS_QUEUE_URL']
    log.info(f'Worker starting, polling queue: {queue_url}')

    while True:
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=20,
        )
        messages = response.get('Messages', [])
        if not messages:
            log.info('No messages received, continuing to poll...')
            continue

        for msg in messages:
            body = json.loads(msg['Body'])
            # SNS wraps the original message in a Message field
            payload = json.loads(body['Message'])
            sleep_seconds = payload['sleep_seconds']

            log.info(f'Processing: sleeping {sleep_seconds}s')
            time.sleep(sleep_seconds)
            log.info(f'Finished processing: {sleep_seconds}')

            sqs.delete_message(
                QueueUrl=queue_url,
                ReceiptHandle=msg['ReceiptHandle'],
            )


if __name__ == '__main__':
    main()
