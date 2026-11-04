# Enabling SSH from Google Cloud web console

In order to use SSH connection from GCP web console, few changes need to be introduced to FortiGate default configuration.

```
config system global
  set strong-crypto disable
end

config system ssh-config
  append ssh-enc-algo aes128-ctr
end

config system interface
  edit port1
    append allowaccess ssh
  next
end
```

Optionally, to match the behaviour of linux VMs in Google Cloud, you can disable passwords for SSH:

```
config system global
  set admin-ssh-password disable
end
```

Last but not least, make sure oslogin is enabled for the VM either explicitly or at the project level.

```
gcloud compute project-info describe --format="json(commonInstanceMetadata.items[])"
gcloud compute instances describe INSTANCE_NAME --zone ZONE --format="json(metadata.items)"
```