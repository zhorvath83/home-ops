#!/usr/bin/env python3

import os
import sys
import requests
import yaml
from typing import List, Set

NETWORKPOLICY_FILE = os.getenv('NETWORKPOLICY_FILE', 'kubernetes/apps/networking/cloudflared/app/networkpolicy.yaml')

def fetch_cloudflare_networks() -> List[str]:
    response = requests.get('https://api.cloudflare.com/client/v4/ips')
    data = response.json()
    return data['result']['ipv4_cidrs'] + data['result']['ipv6_cidrs']

def get_current_cidrs(policy: dict) -> Set[str]:
    cloudflare_egress_rule = next(
        (rule for rule in policy['spec']['egress'] 
         if rule.get('to') and any(to.get('ipBlock') for to in rule['to'])),
        None
    )
    if cloudflare_egress_rule:
        return {to['ipBlock']['cidr'] for to in cloudflare_egress_rule['to']}
    return set()

def update_network_policy(networks: List[str]) -> None:
    with open(NETWORKPOLICY_FILE, 'r') as file:
        policy = yaml.safe_load(file)

    current_cidrs = get_current_cidrs(policy)
    new_cidrs = set(networks)

    added_cidrs = new_cidrs - current_cidrs
    removed_cidrs = current_cidrs - new_cidrs

    # Find the egress rule with Cloudflare IP blocks
    cloudflare_egress_rule = next(
        (rule for rule in policy['spec']['egress'] 
         if rule.get('to') and any(to.get('ipBlock') for to in rule['to'])),
        None
    )

    if cloudflare_egress_rule:
        cloudflare_egress_rule['to'] = [{'ipBlock': {'cidr': cidr}} for cidr in networks]
    else:
        print('Could not find Cloudflare egress rule in the network policy.', file=sys.stderr)
        sys.exit(1)

    with open(NETWORKPOLICY_FILE, 'w') as file:
        yaml.dump(policy, file, default_flow_style=False)

    return added_cidrs, removed_cidrs

def main():
    try:
        networks = fetch_cloudflare_networks()
        added_cidrs, removed_cidrs = update_network_policy(networks)
        
        print('Successfully updated Cloudflare networks in the network policy.')
        if added_cidrs:
            print(f'Added CIDRs: {", ".join(added_cidrs)}')
        if removed_cidrs:
            print(f'Removed CIDRs: {", ".join(removed_cidrs)}')
        
        # If there are changes, write them to a file for the pull request description
        if added_cidrs or removed_cidrs:
            with open('cloudflare_network_changes.txt', 'w') as f:
                if added_cidrs:
                    f.write(f'Added CIDRs: {", ".join(added_cidrs)}\n')
                if removed_cidrs:
                    f.write(f'Removed CIDRs: {", ".join(removed_cidrs)}\n')
    
    except Exception as e:
        print(f'Error updating Cloudflare networks: {e}', file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
