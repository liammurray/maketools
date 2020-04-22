#!/usr/bin/env python3
# -*- mode: python3 -*-

import boto3
import botocore
import click
import os

from local.params import *
from local.utils import *
from local.console_util import *

@click.group()
def values():
  '''
    SSM param helper tool
  '''
  pass

valuesFile = 'values.yml'

def trimKey(path):
  '''
    Removes prefix and tail slash if present
  '''
  if not path:
    return path
  if path.startswith('/'):
    path = path[1:]
  if path.endswith('/'):
    path = path[:-1]
  return path

def normKey(path):
  return '/' + (trimKey(path) or '')

def printVals(vals):
  for key, val in vals.items():
    col = blue if PARAM_REGEX.match(key) else red
    print(col("{}: {}".format(key,val)))

def printList(vals):
   for key in vals:
    col = blue if PARAM_REGEX.match(key) else red
    print(col("{}".format(key)))

def readVals(file):
  ob=loadYaml(valuesFile)
  return ob['ssm']

def getFlat(vals, root):

  if root:
    root = trimKey(root)
  if root:
    parts = root.split('/')
    for p in parts:
      if p not in vals:
        raise Exception('Error locating {}'.format(root))
      vals=vals[p]
    # a/b => /a/b/
    prefix = '/{}/'.format('/'.join(parts))
  else:
    prefix = '/'
  return flatten(vals, prefix)

def readFlat(file, root):
  vals=readVals(file)
  return getFlat(vals, root)


@click.command()
@click.option('-r', '--root', help='Root key')
def show(root):
  '''
    Shows flat values from local
  '''

  print("Values from {} ({}):\n".format(valuesFile, root or '[all]'))
  vals = readFlat(valuesFile, root)
  printVals(vals)


@click.command()
@click.argument('key', nargs=1)
def remove(key):
  '''
    Remove everything at or under key from remote
  '''
  root = normKey(key)
  keys = getNamesUnderPath(root)
  if not keys:
    print('No keys matching {}'.format(root))
    return
  print('\nRemove:\n')

  printList(keys)

  if click.confirm('\nContinue?', default=False):
    for k in keys:
      delParam(k)

@click.command()
@click.argument('root', required=False)
def push(root):
  '''
    Updates remote values from local
  '''

  vals=readFlat(valuesFile, root)
  if not root:
    print('Please specify a prefix:\n')
    printList(vals.keys())
    return

  print('Add:\n')
  printVals(vals)

  new = vals.keys()
  newSet = set(new)

  print('\nRemove:\n')
  prefix = normKey(root)
  old = getNamesUnderPath(prefix)
  toRemove = [x for x in old if x not in newSet]
  printList(toRemove)

  if click.confirm('\nContinue?', default=False):
    for k in toRemove:
      delParam(k)
    for k, v in vals.items():
      if k.endswith('!'):
        k=k[:-1]
        putSecure(k, v)
      else:
        putString(k, v)


# TODO
# @click.command()
# def set_codebuild_token:
#   if not value:
#     raise Error('Need value for token')
#   name = "codebuild/github/token"
#   print('This will set the codebuild token for secret {}'.format(name))
#   if click.confirm('Continue?', default=False):
#     putSecret(name, 'Github token for CodeBuild', value)



values.add_command(show)
values.add_command(push)
values.add_command(remove)
#setup.add_command(set_codebuild_token)

if __name__ == "__main__":
  values()  # pylint: disable=no-value-for-parameter
