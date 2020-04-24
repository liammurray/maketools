#!/usr/bin/env python3
# -*- mode: python3 -*-

import click
from local.cfn_util import *
from local.console_util import *
import base64
import pycurl
from io import BytesIO
from urllib.parse import urlencode
from oauthlib.oauth2 import BackendApplicationClient
from requests.auth import HTTPBasicAuth
from requests_oauthlib import OAuth2Session

def getToken(token_url, client_id, client_secret, scope):
  '''
    Retrieves token from OAuth2 token endpoint
  '''
  auth = HTTPBasicAuth(client_id, client_secret)
  client = BackendApplicationClient(client_id=client_id)
  oauth = OAuth2Session(client=client, scope=scope)
  token = oauth.fetch_token(token_url=token_url, auth=auth)
  return token

def getTokenPyCurl(endpoint, authToken, scope):
  '''
    Retrieves token from OAuth2 token endpoint
  '''
  curl = pycurl.Curl()
  curl.setopt(curl.VERBOSE, True)
  curl.setopt(curl.URL, endpoint)
  curl.setopt(curl.HTTPHEADER, [
    "Authorization: Basic {}".format(authToken),
    "Content-Type: application/x-www-form-urlencoded"
  ])

  postData = {
    "grant_type": "client_credentials",
    "scope": scope
  }
  curl.setopt(curl.POSTFIELDS, urlencode(postData))
  buf = BytesIO()
  curl.setopt(curl.WRITEDATA, buf)
  curl.perform()
  code = curl.getinfo(pycurl.RESPONSE_CODE)
  curl.close()
  return (code, buf.getvalue().decode('utf-8'))

def getStackInfo(stack_name):
  if not stack_name:
    print('Please specifiy a stack name')
    info = getStackNames()
    active=['CREATE_COMPLETE', 'UPDATE_COMPLETE']
    for (name, status) in info:
      col = blue if status in active else dim
      print(col(name), dim(status))
    return
  return getStackOutputDict(stack_name)


@click.group()
def stack():
  '''
    Stack helper tool
  '''
  pass

#
# SSM
#

@click.command()
@click.option('-p', '--prompt/--no-prompt', default=True, help='enable prompts')
@click.option('-r', '--remove', is_flag=True, help='Remove instead of update')
@click.argument('stack_name', required=False)
def ssm(stack_name, remove, prompt):
  """
    Adds or removes ssm entry for test client ID (FullUser)
  """

  si = getStackInfo(stack_name)
  if not si:
    return

  ci = getApiClientInfo(si['PoolArn'], si['ClientIdFullUser'])
  dump(ci)

  if remove:
    deleteSsm(ci, prompt)
  else:
    putSsm(ci, prompt)


#
# INFO
#

@click.command()
@click.argument('stack_name', required=False)
def info(stack_name):
  """
    Shows stack outputs

    Works with any stack. Example:

      /stack.py info orders-dev

  """

  si = getStackInfo(stack_name)
  if not si:
    return

  print
  dump(si)

###
#
# COGNITO
#
#  ./stack.py cognito global-clientcreds-dev

#
@click.command()
@click.argument('stack_name', required=False)
def cognito(stack_name):
  """
    Shows cognito info, app client and related info (assumes stack output names)

    Fetches token for FullUser test client.
    Works only with cognito stack with following outputs:
      PoolArn
      PoolDomainName
      ClientIdFullUser

    /stack.py cognito global-clientcreds-dev
  """

  si = getStackInfo(stack_name)
  if not si:
    return

  print(bold('Client info'))

  ci = getApiClientInfo(si['PoolArn'], si['ClientIdFullUser'])
  dump(ci)

  print(bold('Token server info'))
  adi = getAuthDomainInfo(si['PoolDomainName'])
  dump(adi)

  endpoint='https://{}/oauth2/token'.format(adi['name'])

  try:
    token = getToken(endpoint, ci['id'], ci['secret'], ['orders/rw'])
    print(token)
  except Exception as e:
    print(e)
    if 'invalid_grant' in str(e):
      print(red('Hint: Go to Cognito->App Client Settings and toggle "Enabled Identity Providers"'))


# See swagger issues here:
#  https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-known-issues.html#api-gateway-known-issues-rest-apis

@click.command()
@click.option('-d', '--directory', default='.', help='output directory')
@click.option('-e', '--ext', type=click.Choice(ExtensionVals), default=Extension.none.name, help='extention type')
@click.argument('stack_name', required=False)
def swagger(stack_name, directory, ext):
  '''
    Fetches swagger from API GW

    Works with stack that exports:
      ApiId
      ApiStage
  '''
  si = getStackInfo(stack_name)
  if not si:
    return

  exportSwagger(stack_name, si['ApiId'], si['ApiStage'], directory, ext)

@click.command()
@click.option('-d', '--directory', default='.', help='output directory')
@click.argument('stack_name', required=False)
def sdk(stack_name, directory):
  '''
    Fetches sdk from API GW (openapi generator is better)

    Works with stack that exports:
      ApiId
      ApiStage
  '''
  si = getStackInfo(stack_name)
  if not si:
    return

  exportSdk(stack_name, si['ApiId'], si['ApiStage'], directory)


#
# Route53
#  Works around issue with SAM template
#  Not an issue with CDK
#

@click.command()
@click.option('-p', '--prompt/--no-prompt', default=True, help='enable prompts')
@click.option(
    '-r',
    '--remove',
    is_flag=True,
    default=False,
    help='Remove instead of update')
@click.option('-s', '--stack-name', default='orders', help='stack name')
#@click.argument('key', nargs=-1, type=click.Choice(['foo','bar']))
def route53(stack_name, remove, prompt):

  global enablePrompts
  enablePrompts = prompt

  si = StackInfo(stack_name)
  di = si.getAuthDomainInfo()
  # TODO can we fix script so remove doesn't depend on stack output? (query route53 only)
  modifyUserPoolDomainRoute53AliasEntry(di, not remove)


# stack.add_command(route53)
stack.add_command(info)
stack.add_command(cognito)
stack.add_command(ssm)
stack.add_command(swagger)
stack.add_command(sdk)

if __name__ == "__main__":
  stack()  # pylint: disable=no-value-for-parameter
