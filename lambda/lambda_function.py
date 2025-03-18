# lambda_function.py

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
            
            plan_found = False
            for plan in backup_plans:
                plan_name = plan['BackupPlanName'].lower()
                logger.info(f"Checking backup plan: {plan_name}")
                
                if 'met-bronze-backup' in plan_name:
                    tag_value = 'Bronze' if 'eu' not in plan_name else 'Bronze-EU'
                elif 'met-gold-backup' in plan_name:
                    tag_value = 'Gold' if 'eu' not in plan_name else 'Gold-EU'
                elif 'met-silver-backup' in plan_name:
                    if 'pgdata' in plan_name:
                        tag_value = 'Silver-pgdata'
                    elif 'eu' in plan_name:
                        tag_value = 'Silver-EU'
                    else:
                        tag_value = 'Silver'
                else:
                    continue
                
                logger.info(f"Applying tag MetBackupPlan={tag_value} to {instance_id}")
                ec2.create_tags(Resources=[instance_id], Tags=[{'Key': 'MetBackupPlan', 'Value': tag_value}])
                plan_found = True
                break
            
            if not plan_found:
                logger.info(f"No matching backup plan found for {instance_id}")
        except Exception as e:
            logger.error(f"Error retrieving backup plans: {str(e)}")
            raise e
    elif state == 'stopping':
        logger.info(f'No action needed for {instance_id} in state {state}')
