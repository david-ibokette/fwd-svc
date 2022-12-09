#!/opt/homebrew/bin/python3
import re
import argparse
import os
import sys


def get_running_forwards():
    cmd = "ps -e -o command | grep port-forward | grep -v grep"
    # cmd = "/Users/dibokette/bin/port-forward_temp"
    stream = os.popen(cmd)
    return [s.strip() for s in stream.readlines()]


def get_pods(pod_filter):
    if not pod_filter or re.search(r'\s', pod_filter):
        cmd = "kubectl get pods | grep staging"
        # cmd = "/Users/dibokette/bin/kpods_temp | grep staging"
    else:
        cmd = f"kubectl get pods  | grep staging | grep {pod_filter}"
        # cmd = f"/Users/dibokette/bin/kpods_temp | grep staging | grep {pod_filter}"
    stream = os.popen(cmd)
    stripped = [s.strip() for s in stream.readlines()]
    return [re.sub(r'^(\S+).*$', r'\1', s) for s in stripped]


parser = argparse.ArgumentParser()
parser.add_argument("--grep", help="search pattern")
parser.add_argument("--ps", help="print the running local service forwarders", action="store_true")
parser.add_argument("--pods", help="print the running pods", action="store_true")
parser.add_argument("--lport", help="local port")
parser.add_argument("--pport", help="pod port")
args = parser.parse_args()

local_port = 8080
pod_port = 8080

if args.ps:
    output = get_running_forwards()
    for x in range(len(output)):
        print(output[x], end='')
    exit(0)

if args.pods:
    output = get_pods(args.grep)
    for x in range(len(output)):
        print(output[x], end='')
    exit(0)

if args.lport:
    local_port = int(args.lport)

if args.pport:
    pod_port = int(args.pport)

running = get_running_forwards()
pods = get_pods(args.grep)

if len(pods) == 0:
    print("Did not get any pods", file=sys.stderr)
    exit(1)

name_to_running_map = {re.sub(r'^\w+\s[\w-]+\s(\w+)-staging-.+$', r'\1', running[i]): running[i] for i in
                       range(0, len(running))}

name_to_pod_map = {re.sub(r'^([\w-]+?)-staging-.+$', r'\1', pods[i]): pods[i] for i in range(0, len(pods))}

# remove entries from name_to_pod_map that are in name_to_running_map
for key in name_to_running_map.keys():
    name_to_pod_map.pop(key, None)

podname_ordered = sorted(name_to_pod_map.keys())

for index in range(0, len(podname_ordered)):
    print(f"{index}: {podname_ordered[index]}")

ans = input("which one?")

if re.match(r'^quit|^q', ans, re.IGNORECASE):
    exit(0)

if not re.match(r'^\d+$', ans):
    print("Need a number", file=sys.stderr)
    exit(1)

chosen_idx = int(ans)

if chosen_idx > len(name_to_pod_map):
    print("Number is out of range", file=sys.stderr)
    exit(1)

chosen_pod = name_to_pod_map[podname_ordered[chosen_idx]]

kcmd = f'kubectl port-forward {chosen_pod} {local_port}:{pod_port} &'

print("Currently Running:")
print(running)
print()

ans = input(f'Run command: "{kcmd}"?')

if not re.match(r'^y', ans, re.IGNORECASE):
    print("Cancelling", file=sys.stderr)
    exit(0)

print(f'Running command: "{kcmd}"')
os.system(kcmd)


