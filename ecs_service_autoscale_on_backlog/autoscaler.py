import os
import logging

import boto3

ecs = boto3.client('ecs')
sqs = boto3.client('sqs')

logfmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)
_ch = logging.StreamHandler()
_ch.setFormatter(logging.Formatter(logfmt))
_rootlogger = logging.getLogger()
if _rootlogger.handlers:  # undo AWS Lambda's monkeypatching of the logging module so we can add our own stream handler without duplicating messages...
    for handler in _rootlogger.handlers:
        _rootlogger.removeHandler(handler)
_rootlogger.setLevel(logging.INFO)
_rootlogger.addHandler(_ch)


def lambda_handler(event, context):
    cluster = os.environ['CLUSTER_NAME']
    service = os.environ['SERVICE_NAME']
    queue_url = os.environ['SQS_QUEUE_URL']
    minimum_tasks = int(os.environ['MINIMUM_TASKS'])
    maximum_tasks = int(os.environ['MAXIMUM_TASKS'])
    backlog_per_task_target = int(os.environ['BACKLOG_PER_TASK_TARGET'])
    log.debug(f'{cluster=} {service=} {queue_url=} {minimum_tasks=} {maximum_tasks=} {backlog_per_task_target=}')

    r = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=['ApproximateNumberOfMessages']
    )
    number_of_messages = int(r['Attributes']['ApproximateNumberOfMessages'])
    computed_target_count = 0 if number_of_messages == 0 else round(number_of_messages / backlog_per_task_target)

    r = ecs.describe_services(
        cluster=cluster,
        services=[service],

    )
    current_count = r['services'][0]['runningCount']
    desired_count = r['services'][0]['desiredCount']

    # step by halves towards target to make scaling less reactive. in the future, we can implement more sophisticated scaling here
    # specifically, we should target a desired SQS processing delay time rather than use a hardcoded backlog per task scaling factor
    new_desired_count = 0 if number_of_messages == 0 else  max(1, round((desired_count + computed_target_count) / 2))
    if new_desired_count > maximum_tasks:
        new_desired_count = maximum_tasks
    elif new_desired_count < minimum_tasks:
        new_desired_count = minimum_tasks

    log.info(f'Current: {current_count=} {desired_count=} with backlog of {number_of_messages=}.')
    log.info(f'Instantaneous computed target: {computed_target_count=}. Actual desired count to set: {new_desired_count=}.')
    ecs.update_service(
        cluster=cluster,
        service=service,
        desiredCount=new_desired_count
    )
