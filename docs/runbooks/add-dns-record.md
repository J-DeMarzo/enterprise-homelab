# Runbook: Add a DNS record

**When:** A host with a static IP is added or changed.

## Steps
1. Open the Technitium console on the **primary**: `http://dns1.demarzo.lab:5380`.
2. **Zones → `demarzo.lab` → Add Record**
   - Name: short hostname (e.g. `ops`)
   - Type: `A`
   - IPv4: the host's static address
   - TTL: default
3. If the reverse zone exists, tick **Add reverse (PTR) record**.
4. Save.

### Or from `ops`, through the API
```bash
T=$(cat ~/.config/technitium/dns1.token)
curl -s http://10.12.5.53:5380/api/zones/records/add \
  --data-urlencode "token=$T" -d zone=demarzo.lab -d domain=<name>.demarzo.lab \
  -d type=A -d ttl=3600 -d ipAddress=<ip> -d ptr=true    # ptr=true also writes the PTR
```
⚠️ With `ptr=true` and **no** reverse zone for that VLAN (Security, DMZ), Technitium rejects the whole request ("No reverse zone available to add PTR record"), and the A record isn't added either. Leave out `ptr=true` there.

The `ops` API user can add and change records, but not zone options ([dns.md](../architecture/dns.md#api-access)).

## Check that it worked
Query **both** servers directly. They should give the same answer:
```bash
host <name>.demarzo.lab 10.12.5.53
host <name>.demarzo.lab 10.12.5.54
```
If dns2 doesn't have the record within a few seconds, it hasn't synced. The catalog notifies dns2 on each change. Without notify, dns2 waits for its 15-minute SOA refresh. Check the zone's SOA serial on both:
```bash
host -t SOA demarzo.lab 10.12.5.53
host -t SOA demarzo.lab 10.12.5.54
```

## Afterwards
Add the record to the table in [dns.md](../architecture/dns.md#records) and commit.
