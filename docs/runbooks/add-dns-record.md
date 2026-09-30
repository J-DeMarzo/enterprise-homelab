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

## Check that it worked
Query **both** servers directly. They should give the same answer:
```bash
host <name>.demarzo.lab 10.12.5.53
host <name>.demarzo.lab 10.12.5.54
```
If dns2 doesn't have the record yet, it hasn't synced. Check the zone's SOA serial on both:
```bash
host -t SOA demarzo.lab 10.12.5.53
host -t SOA demarzo.lab 10.12.5.54
```

## Afterwards
Add the record to the table in [dns.md](../architecture/dns.md#records) and commit.
