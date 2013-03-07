#!/usr/bin/python
import json
import os
import platform
import signal
import sys
import requests
import time
import traceback
from bson import json_util
from optparse import OptionParser
from games import run_games

ALIVE = True

def on_sigint(signal, frame):
  global ALIVE
  if ALIVE:
    sys.stderr.write('Shutting down gracefully...\n')
    ALIVE = False
    return

  sys.stderr.write('Hard shutdown!  Tasks may be incomplete\n')
  sys.exit(0)

def get_worker_info():
  return {
    'uname': platform.uname(),
  }

def request_task(fishtest_dir, worker_info, password, remote):
  payload = {
    'worker_info': worker_info,
    'password': password,
  }
  r = requests.post(remote + '/api/request_task', data=json.dumps(payload))
  task = json.loads(r.text, object_hook=json_util.object_hook)

  if 'task_waiting' in task:
    return
  if 'error' in task:
    raise Exception('Error from remote: %s' % (task['error']))

  run_games(fishtest_dir, worker_info, password, remote, task['run'], task['task_id'])

def worker_loop(fishtest_dir, worker_info, password, remote):
  global ALIVE
  while ALIVE:
    print 'polling for tasks...'
    try:
      request_task(fishtest_dir, worker_info, password, remote)
    except:
      sys.stderr.write('Exception from worker:\n')
      traceback.print_exc(file=sys.stderr)

    time.sleep(10)

def main():
  parser = OptionParser()
  parser.add_option('-n', '--host', dest='host', default='54.235.120.254')
  parser.add_option('-p', '--port', dest='port', default='6543')
  parser.add_option('-c', '--concurrency', dest='concurrency', default='1')
  (options, args) = parser.parse_args()

  if len(args) != 3:
    sys.stderr.write('%s [username] [password] [fishtest_dir]\n' % (sys.argv[0]))
    sys.exit(1)

  remote = 'http://%s:%s' % (options.host, options.port)
  print 'Launching with %s' % (remote)

  worker_info = get_worker_info()
  worker_info['concurrency'] = options.concurrency
  worker_info['username'] = args[0]

  fishtest_dir = args[2]
  if not os.path.exists(fishtest_dir):
    raise Exception('Testing directory does not exist: %s' % (fishtest_dir))

  signal.signal(signal.SIGINT, on_sigint)
  signal.signal(signal.SIGTERM, on_sigint)
  worker_loop(fishtest_dir, worker_info, args[1], remote)

if __name__ == '__main__':
  main()
