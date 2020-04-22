#!/usr/bin/env python3
# -*- mode: python3 -*-

import yaml


def loadYaml(fileName):
  #debug("Loading %s" % fileName, 2)
  with open(fileName, "r") as stream:
    return yaml.load(stream, Loader=yaml.FullLoader)

def dump(ob):
  # Use YAML for raw output of dictionary
  print(yaml.safe_dump(ob, default_flow_style=False))

def nest(path, val={}):
  """
    nest('a')   =>  {'a': {}}
    nest('a/b') =>  {'a': {'b': {}}}
  """
  parts = [p for p in path.split('/') if p]
  child = val
  for key in reversed(parts):
    parent = {}
    parent[key] = child
    child = parent
  return child


def merge(src, dest):
  for key, value in src.items():
    if isinstance(value, dict):
      node = dest.setdefault(key, {})
      merge(value, node)
    else:
      dest[key] = value
  return dest


def flattenx(ob, prefix):
  flat={}
  for key, value in ob.items():
    if isinstance(value, dict):
      sub=flatten(value, "{}/".format(key))
      for skey, svalue in sub.items():
        flat['{}/{}'.format(key,skey)] = svalue
    else:
      flat[key] = value
  return flat


def flatten(ob, prefix=''):
  flat={}
  for key, val in ob.items():
    cprefix = prefix + key
    if isinstance(val, dict):
      sub=flatten(val, cprefix + '/')
      for skey, sval in sub.items():
        flat[skey] = sval
    else:
      flat[prefix + key] = val
  return flat
