import boto3
import logging

ec2 = boto3.client('ec2')
backup = boto3.client('backup')
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Received event: {event}")

    instance_id = event['detail']['instance-id']
    state = event['detail']['state']

    logger.info(f"Processing instance {instance_id} in state {state}")

    if state == 'stopped':
        ec2.create_tags(Resources=[instance_id], Tags=[{'Key': 'MetBackupPlan', 'Value': 'Tin'}])
        logger.info(f'Set MetBackupPlan to Tin for {instance_id}')
    elif state == 'running':
        try:
            backup_plans = backup.list_backup_plans()['BackupPlansList']
            logger.info(f"Backup plans found: {backup_plans}")

            for plan in backup_plans:
                if 'met-gold-backup' in plan['BackupPlanName'].lower():
                    tag_value = 'Gold'
                    ec2.create_tags(Resources=[instance_id], Tags=[{'Key': 'MetBackupPlan', 'Value': tag_value}])
                    break
        except Exception as e:
            logger.error(f"Error retrieving backup plans: {str(e)}")
            raise e
    elif state == 'stopping':
        logger.info(f'No action needed for {instance_id} in state {state}')
