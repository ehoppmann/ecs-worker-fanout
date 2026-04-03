import json
import os
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
    sns = boto3.client('sns')
    topic_arn = os.environ['SNS_TOPIC_ARN']

    for i in range(1, 11):
        payload = {'sleep_seconds': i}
        log.info(f'Publishing message {i}/10: {payload}')
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(payload),
        )

    log.info('Scheduler complete. Published 10 messages.')


if __name__ == '__main__':
    main()
