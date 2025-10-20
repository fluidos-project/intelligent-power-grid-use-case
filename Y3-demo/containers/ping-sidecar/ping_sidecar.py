import os
import time
import subprocess
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

# Config
host = os.getenv('HOST', '172.25.xx.xx')
pushgateway_url = os.getenv('PUSHGATEWAY_URL', '172.25.xx.xx:9091')
interval = int(os.getenv('INTERVAL', '2'))
fallback_value = float(os.getenv('FALLBACK_VALUE', '400'))
switch_after = int(os.getenv('SWITCH_AFTER', '500'))
NAMESPACE = "fluidos"

def get_flavor_name():
    try:
        result = subprocess.run(
            ['kubectl', 'get', 'flavor', '-n', NAMESPACE, '-o', "jsonpath={.items[0].metadata.name}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        print(f"Failed to get flavor name: {result.stderr.strip()}")
    except Exception as e:
        print(f"Exception while getting flavor name: {e}")
    return None

def get_domain(flavor_name):
    if not flavor_name:
        return "unknown.fluidos.eu"
    try:
        result = subprocess.run(
            ['kubectl', 'get', 'flavor', flavor_name, '-n', NAMESPACE, '-o', "jsonpath={.spec.owner.domain}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        print(f"Failed to get domain: {result.stderr.strip()}")
    except Exception as e:
        print(f"Exception while getting domain: {e}")
    return "unknown.fluidos.eu"

def update_flavor_latency(flavor_name, latency):
    try:
        patch = f'''{{
  "spec": {{
    "flavorType": {{
      "typeData": {{
        "properties": {{
          "additionalProperties": {{
            "latency": {latency}
          }}
        }}
      }}
    }}
  }}
}}'''
        result = subprocess.run(
            [
                'kubectl', 'patch', 'flavor', flavor_name,
                '-n', NAMESPACE,
                '--type', 'merge',
                '-p', patch
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        if result.returncode == 0:
            print(f" pdated flavor {flavor_name} with latency={latency}")
        else:
            print(f"Failed to update flavor: {result.stderr.strip()}")
    except Exception as e:
        print(f"Exception while updating flavor: {e}")

def ping(host):
    try:
        result = subprocess.run(
            ['ping', '-c', '1', host],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        if result.returncode == 0:
            return float(result.stdout.split('time=')[1].split(' ms')[0])
    except Exception:
        return None

if __name__ == '__main__':
    flavor_name = get_flavor_name()
    cluster_domain = get_domain(flavor_name)
    print(f"Flavor: {flavor_name}, Cluster domain: {cluster_domain}")

    start_time = time.time()
    switched = False
    while True:
        registry = CollectorRegistry()
        latency_gauge = Gauge('fluidos_latency', 'Ping latency in ms', ['cluster'], registry=registry)

        elapsed = time.time() - start_time
        if elapsed < switch_after:
            latency = ping(host)
        else:
            latency = fallback_value
            if not switched and flavor_name: 
                update_flavor_latency(flavor_name, latency)
                switched = True
                
        if latency is not None:
            latency_gauge.labels(cluster=cluster_domain).set(latency)
            print(f"Latency to {host}: {latency} ms")

        push_to_gateway(pushgateway_url, job='ping_sidecar', registry=registry)
        time.sleep(2)

