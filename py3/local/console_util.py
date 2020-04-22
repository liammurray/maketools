
import string
from datetime import datetime, date
from dateutil.relativedelta import relativedelta
from colorama import init, Fore, Back, Style
import yaml
import click

# colorama
init()


def asYaml(ob):
  return yaml.safe_dump(ob, default_flow_style=False)


def get_value_or_stdin(ctx, param, value):
  '''
    click helper (for arg that if null implies read from stdin)
  '''
  instr = click.get_text_stream('stdin')
  # isatty() returns true if interactive (false if stdin piped)
  if not value and not instr.isatty():
    return instr.read().strip()
  else:
    return value


def bold(text):
  '''
    Usage: print bold("bold text")
  '''
  return Style.BRIGHT + text + Style.NORMAL


def blue(text):
  return Fore.BLUE + text + Fore.RESET


def green(text):
  return Fore.GREEN + text + Fore.RESET


def red(text):
  return Fore.RED + text + Fore.RESET


def dim(text):
  return Style.DIM + text + Style.NORMAL


def bred(text):
  return Style.BRIGHT + Fore.RED + text + Fore.RESET + Style.NORMAL


def set_title(text):
  print(colorama.ansi.set_title(text))


ALL_ATTRS = ['years', 'months', 'days', 'hours', 'minutes', 'seconds']


def human_readable(delta, attrs):
  return ['%d %s' % (getattr(delta, attr), getattr(delta, attr) > 1 and attr or attr[:-1])
          for attr in attrs if getattr(delta, attr)]


def to_relativedelta(tdelta):
  return relativedelta(
      seconds=int(tdelta.total_seconds()),
      microseconds=tdelta.microseconds
  )


def format_time(dt, attrs=ALL_ATTRS, time_format="%H:%M:%S %Y-%m-%d", max_attr=0, just_now_threshold_secs=60):
  '''
    Examples:

    format_time(datetime.datetime.now()-timedelta(seconds=2), just_now_threshold_secs=2)
      16:08:09 2019-01-03 (2 seconds ago)

    format_time(datetime.datetime.now()-timedelta(seconds=2), just_now_threshold_secs=3, time_format="%Y-%m-%d")
      2019-01-03 (just now)

    To omit relative time pass [] for attrs

    format_time(datetime.datetime.now()-timedelta(seconds=2), attrs=[])
      16:09:09 2019-01-03

    format_time(datetime.datetime.now()-timedelta(seconds=2), attrs=[], time_format="%m/%d/%Y")
      01/03/2019 # Probably should just call dt.strftime() in this case

  '''
  formatted_time = dt.strftime(time_format) if time_format else None
  tdelta = datetime.now(dt.tzinfo) - dt
  rdelta = to_relativedelta(tdelta)
  parts = human_readable(delta=rdelta, attrs=attrs)
  if max_attr > 0:
    # Limit to first N non-0 components
    parts = parts[:max_attr]
  formatted_delta = string.join(parts, ' ')
  if formatted_time:
    out = formatted_time
    if formatted_delta:
      if tdelta.total_seconds() < just_now_threshold_secs:
        out += " (just now)"
      else:
        out += " ({} ago)".format(formatted_delta)
  elif formatted_delta:
    if tdelta.total_seconds() < just_now_threshold_secs:
      out += "just now"
    else:
      out = "{} ago".format(formatted_delta)
  else:
    raise Exception("Unable to format time")
  return out
