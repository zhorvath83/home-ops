#!/usr/bin/env zx
import fs from 'fs';
import yaml from 'js-yaml';

$.verbose = false;

const NETWORKPOLICY_FILE = process.env.NETWORKPOLICY_FILE || 'kubernetes/apps/networking/cloudflared/app/networkpolicy.yaml';

async function fetchCloudflareNetworks() {
  const response = await fetch('https://api.cloudflare.com/client/v4/ips');
  const body = await response.json();
  return body.result.ipv4_cidrs.concat(body.result.ipv6_cidrs);
}

async function updateNetworkPolicy(networks) {
  const fileContents = await fs.promises.readFile(NETWORKPOLICY_FILE, 'utf8');
  const policy = yaml.load(fileContents);

  // Find the egress rule with Cloudflare IP blocks
  const cloudflareEgressRule = policy.spec.egress.find(rule => 
    rule.to && rule.to.some(to => to.ipBlock && to.ipBlock.cidr)
  );

  if (cloudflareEgressRule) {
    cloudflareEgressRule.to = networks.map(cidr => ({ ipBlock: { cidr } }));
  } else {
    console.error('Could not find Cloudflare egress rule in the network policy.');
    process.exit(1);
  }

  const updatedYaml = yaml.dump(policy, { lineWidth: -1 });
  await fs.promises.writeFile(NETWORKPOLICY_FILE, updatedYaml, 'utf8');
}

async function main() {
  try {
    const networks = await fetchCloudflareNetworks();
    await updateNetworkPolicy(networks);
    console.log('Successfully updated Cloudflare networks in the network policy.');
  } catch (error) {
    console.error('Error updating Cloudflare networks:', error);
    process.exit(1);
  }
}

main();
