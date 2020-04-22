#!/usr/bin/env python3
# -*- mode: python3 -*-

import click
from local.cfn_util import *

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
@click.option('-s', '--stack-name', default='orders', help='stack name')
def ssm(stack_name, remove, prompt):

  global enablePrompts
  enablePrompts = prompt

  si = StackInfo(stack_name)
  userInfo = si.getUserInfo()
  if remove:
    deleteSsm(userInfo)
  else:
    putSsm(userInfo)


#
# INFO
#

@click.command()
@click.option('-s', '--stack-name', default='orders', help='stack name')
@click.option('-c', '--cache-name', default=None, help='stack name')
def info(stack_name, cache_name):

  si = StackInfo(stack_name, cache_name)

  print("Auth domain info", si.getAuthDomainInfo())
  print("User info", si.getUserInfo())


# See swagger issues here:
#  https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-known-issues.html#api-gateway-known-issues-rest-apis

@click.command()
@click.option('-s', '--stack-name', default='orders', help='stack name')
@click.option('-d', '--directory', default='.', help='output directory')
@click.option('-e', '--ext', type=click.Choice(ExtensionVals), default=Extension.none.name, help='extention type')
def swagger(stack_name, directory, ext):
  si = StackInfo(stack_name)
  exportSwagger(si, directory, ext)

@click.command()
@click.option('-s', '--stack-name', default='orders', help='stack name')
@click.option('-d', '--directory', default='.', help='output directory')
def sdk(stack_name, directory):
  si = StackInfo(stack_name)
  exportSdk(si, directory)


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


stack.add_command(route53)
stack.add_command(info)
stack.add_command(ssm)
stack.add_command(swagger)
stack.add_command(sdk)

if __name__ == "__main__":
  stack()  # pylint: disable=no-value-for-parameter
