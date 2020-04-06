
# -*- mode: python3 -*-
#
import boto3
import click
import string
import yaml
from enum import Enum
import pathlib
import os
import io

cognitoClient = boto3.client('cognito-idp')
cloudformation = boto3.resource('cloudformation')
ssmClient = boto3.client('ssm')
route53client = boto3.client('route53')

def getStackOutputDict(stackName):
  print('Getting stack output for {}'.format(stackName))
  stack = cloudformation.Stack(stackName)
  d = {}
  for out in stack.outputs:
    key = out['OutputKey']
    d[key] = out['OutputValue']
  return d

def toYaml(ob):
  return yaml.safe_dump(ob, default_flow_style=False)

def fromYaml(text):
  return yaml.load(text, Loader=yaml.FullLoader)

def ensureSuffix(name, s = '.yaml'):
  p = pathlib.Path(name)
  if not p.suffix:
    p = p.with_suffix(s)
  return p

class StackInfo(object):

  def __init__(self, stackName, cacheName=None):
    self.stackName = stackName
    if cacheName:
      self.cacheName=ensureSuffix(cacheName)
      try:
        self.loadCache()
      except:
        self.info = getStackOutputDict(stackName)
        self.saveCache()
    else:
      self.info = getStackOutputDict(stackName)

  def saveCache(self):
    with open(self.cacheName, 'wt') as f:
      print(toYaml(self.info), file=f)

  def loadCache(self):
    with open(self.cacheName, 'rt') as f:
      self.info = fromYaml(f.read())

  def getUserInfo(self, key='TestClientId'):
    clientId = self.info[key]
    userPoolId = self.info['UserPoolId']
    res = cognitoClient.describe_user_pool_client(
        ClientId=clientId, UserPoolId=userPoolId)
    info = res['UserPoolClient']
    return {
        'name': info['ClientName'],
        'id': info['ClientId'],
        'secret': info['ClientSecret']
    }

  def getAuthDomainInfo(self):
    domain = self.info['UserPoolDomainName']

    res = cognitoClient.describe_user_pool_domain(Domain=domain)
    info = res['DomainDescription']
    dist = info['CloudFrontDistribution']
    status = info['Status']

    return {'name': domain, 'dist': dist, 'status': status}



Extension = Enum('Extension', 'postman aws none')
ExtensionVals = [a.name for a in Extension]


def fixupSwagger(fileName):
  '''
  #
  # API GW writes out:
  #   url: https://dev-api.nod15c.com/{basePath}
  #   basePath: /orders
  #
  # This fixes by removing the slash before the basePath variable in the URL
  #
  # sed -i '' 's/\/{basePath}/{basePath}/g' ./$OUT_FILE
  '''
  with open(fileName) as f:
    data = f.read()
  with open(fileName, 'w') as f:
    f.write(data.replace("/{basePath}", "{basePath}"))



def exportSwagger(si, directory, ext=Extension.none):
  ext = 'yaml'

  args = {}
  args['restApiId'] = si.info['ApiId']
  args['stageName'] = si.info['ApiStage']
  args['exportType'] = 'oas30'
  args['accepts'] = 'application/{}'.format(ext)

  params = {}
  if ext == Extension.aws:
    params['extensions'] = 'integrations'
    suffix = '-aws'
  elif type == Extension.postman:
    params['extensions'] = 'postman'
    suffix = '-postman'
  else:
    suffix = ''

  client = boto3.client('apigateway')
  response = client.get_export(parameters=params, **args)

  #  stackName-api.yaml
  #  stackName-api-aws.yaml
  #  stackName-api-postman.yaml
  outName = '{}-api{}.{}'.format(si.stackName, suffix, ext)
  outPath = os.path.join(directory, outName)
  print('Saving swagger: {}'.format(outPath))
  with open(outPath, 'wt') as f:
    body = response['body']
    for chunk in body:
      f.write(chunk.decode('utf-8'))

  fixupSwagger(outPath)

def exportSdk(si, directory):
  type='javascript'
  args = {}
  args['restApiId'] = si.info['ApiId']
  args['stageName'] = si.info['ApiStage']
  args['sdkType'] = type

  client = boto3.client('apigateway')
  response = client.get_sdk(**args)

  outName = '{}-client-{}-{}.zip'.format(si.stackName, type, si.info['ApiStage'])
  outPath = os.path.join(directory, outName)
  print('Saving sdk client zip: {}'.format(outPath))
  with open(outPath, 'wb') as f:
    body = response['body']
    for chunk in body:
      f.write(chunk)


def putSsm(userInfo, base='/api/clientcreds'):
  '''
    Saves user info (from StackInfo.getUserInfo) to SSM
  '''
  name = '{}/{}'.format(base, userInfo['name'])
  clientId = userInfo['id']
  secret = userInfo['secret']
  value = "{}:{}".format(clientId, secret)
  print("Setting SSM secret for {}".format(name))
  if not enablePrompts or click.confirm('Continue?', default=False):
    ssmClient.put_parameter(
        Name=name,
        Description="Client ID and secret for {}".format(name),
        Value=value,
        Type="SecureString",
        Overwrite=True)


def deleteSsm(userInfo, base='/api/clientcreds'):
  name = '{}/{}'.format(base, userInfo['name'])
  print(("Removing SSM secret for {}".format(name)))
  if not enablePrompts or click.confirm('Continue?', default=False):
    ssmClient.delete_parameter(Name=name)



def getApexDomain(domain):
  '''
    Returns something like "nod15c.com."
  '''
  # Handle "foo.nod15c.com" and "foo.nod15c.com."
  parts = [p for p in domain.split('.') if p]
  return string.join(parts[-2:], '.') + '.'


def getHostedZoneInfo(name="nod15c.com."):
  # Assumes relatively small number
  res = route53client.list_hosted_zones()
  if res['IsTruncated']:
    raise Exception("FixMe")
  zones = res['HostedZones']
  try:
    info = next(zone for zone in zones if zone['Name'] == name)
    # print info
    id = info['Id']
    # /hostedzone/Z2X325LEDJ47O
    idShort = id[id.rfind('/') + 1:]
    return {'domain': name, 'zoneId': idShort, 'zoneIdFullyQualified': id}
  except:
    raise Exception("Not found: {}".format(name))


def modifyUserPoolDomainRoute53AliasEntry(domainInfo, update=True):
  '''
    Adds or removes route53 alias given domain info from StackInfo.getAuthDomainInfo()
  '''
  domain = domainInfo['name']
  apex = getApexDomain(domain)
  info = getHostedZoneInfo(apex)

  # Well-known zone id for cloudfront
  cfZoneId = 'Z2FDTNDATAQYW2'

  zoneId = info['zoneId']
  alias = domainInfo['dist']

  if update:
    action = 'UPSERT'
    comment = "Create alias for user pool domain"
  else:
    action = 'DELETE'
    comment = "Remove alias for user pool domain"

  batch = {
      "Comment":
          comment,
      "Changes": [{
          "Action": action,
          "ResourceRecordSet": {
              "Name": domain,
              "Type": "A",
              "AliasTarget": {
                  "HostedZoneId": cfZoneId,
                  "DNSName": alias,
                  "EvaluateTargetHealth": False
              }
          }
      }]
  }

  if update:
    print(("Create A record Alias: {} ({}) => {}".format(domain, zoneId, alias)))
    if not enablePrompts or click.confirm('Continue?', default=False):
      res = route53client.change_resource_record_sets(
          HostedZoneId=zoneId, ChangeBatch=batch)
  else:
    print(("Delete A record Alias: {} ({})".format(domain, zoneId)))
    if not enablePrompts or click.confirm('Continue?', default=False):
      res = route53client.change_resource_record_sets(
          HostedZoneId=zoneId, ChangeBatch=batch)
  print(("Submitted (status={})".format(res['ChangeInfo']['Status'])))



