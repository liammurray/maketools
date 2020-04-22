# -*- mode: python3 -*-

import boto3
import botocore
import click
import os
import yaml
import re
from .utils import *


ssmClient = boto3.client('ssm')
smClient = boto3.client('secretsmanager')


PARAM_REGEX=re.compile("^[a-zA-Z0-9_\.\-/]+$")

def getNamesUnderPath(path):
  # aws ssm get-parameters-by-path --path $PARAM_PATH --recursive | jq -r '.Parameters[].Name'
  try:
    res = ssmClient.get_parameters_by_path(Path=path, Recursive=True)
    return [p['Name'] for p in res['Parameters']]
  except botocore.exceptions.ClientError as e:
    code = e.response['Error']['Code']
    if code != 'ParameterNotFound':
      print(e)
  return []


def putString(name, value):
  print("{} => {}".format(name, value))
  ssmClient.put_parameter(Name=name, Value=value, Type="String", Overwrite=True)

def putSecure(name, value):
  print("{}! => {}".format(name, value))
  ssmClient.put_parameter(
      Name=name, Value=value, Type="SecureString", Overwrite=True)


def delParam(name):
  print("delete: {}".format(name), end='')
  try:
    ssmClient.delete_parameter(Name=name)
    print()
  except botocore.exceptions.ClientError as e:
    code = e.response['Error']['Code']
    if code != 'ParameterNotFound':
      print(" ", e)
    else:
      print(" [Missing]")



def createSecret(name, desc, value):
  print("Creating secret {}".format(name))
  smClient.create_secret(
    Name=name,
    Description=desc,
    SecretString=value
  )

def putSecret(name, desc, value):
  try:
    smClient.put_secret_value(
      SecretId=name,
      SecretString=value
    )
  except botocore.exceptions.ClientError as e:
    code = e.response['Error']['Code']
    if code == 'ResourceNotFoundException':
      createSecret(name, desc, value)


def delSecret(name):
  smClient.delete_secret(
    SecretId=name,
    ForceDeleteWithoutRecovery=True
  )
