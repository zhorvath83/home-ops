#!/usr/bin/env python3

import os
import sys
import requests
from ruamel.yaml import YAML

NETWORKPOLICY_FILE = os.getenv('NETWORKPOLICY_FILE', 'kubernetes/apps/networking/cloudflared/app/networkpolicy.yaml')

def fetch_cloudflare_networks():
    response = requests.get('https://api.cloudflare.com/client/v4/ips')
    data = response.json()
    return data['result']['ipv4_cidrs'] + data['result']['ipv6_cidrs']

def update_network_policy(networks):
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)

    with open(NETWORKPOLICY_FILE, 'r') as file:
        policy = yaml.load(file)

    cloudflare_egress_rule = next(
        (rule for rule in policy['spec']['egress'] 
         if rule.get('to') and any(to.get('ipBlock') for to in rule['to'])),
        None
    )

    if cloudflare_egress_rule:
        current_cidrs = {to['ipBlock']['cidr'] for to in cloudflare_egress_rule['to']}
        new_cidrs = set(networks)

        added_cidrs = new_cidrs - current_cidrs
        removed_cidrs = current_cidrs - new_cidrs

        cloudflare_egress_rule['to'] = [{'ipBlock': {'cidr': cidr}} for cidr in networks]
    else:
        print('Could not find Cloudflare egress rule in the network policy.', file=sys.stderr)
        sys.exit(1)

    with open(NETWORKPOLICY_FILE, 'w') as file:
        yaml.dump(policy, file)

    return added_cidrs, removed_cidrs

def main():
    try:
        networks = fetch_cloudflare_networks()
        added_cidrs, removed_cidrs = update_network_policy(networks)
        
        print(f'Total CIDRs: {len(networks)}')
        if added_cidrs:
            print(f'Added CIDRs: {", ".join(added_cidrs)}')
        if removed_cidrs:
            print(f'Removed CIDRs: {", ".join(removed_cidrs)}')
    
    except Exception as e:
        print(f'Error updating Cloudflare networks: {e}', file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
