from airflow import DAG
from airflow.operators.python_operator import PythonOperator
from datetime import datetime, timedelta
import pendulum

local_tz = pendulum.timezone("Asia/Singapore")

def print_datetime_task(execution_date: datetime, **kwargs):
    local_dt = local_tz.convert(execution_date)
    print("Original execution:", execution_date)
    print("  Original exec TZ:", execution_date.tzinfo)
    print("   Local execution:", local_dt)
    print("     Local exec TZ:", local_dt.tzinfo)

default_args=dict(
    start_date=datetime(
        year=2019,
        month=1,
        day=1,
        tzinfo=local_tz),  # 1am at local time
    owner='Airflow'
)

dag_id = 'print_datetime_dag'
dag = DAG(dag_id,
          default_args=default_args,
          schedule_interval="0 1 * * *")  # Every 1am (local)

task_id = 'print_datetime_task'
task = PythonOperator(
    task_id=task_id,
    provide_context=True,
    python_callable=print_datetime_task,
    dag=dag,
)
