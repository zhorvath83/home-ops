**🔹  Mozilla SOPS**

The integrity of each document is guaranteed by calculating a Message Authentication Code (MAC) that is stored encrypted by the data key. When decrypting a document, the MAC should be recalculated and compared with the MAC stored in the document to verify that no fraudulent changes have been applied. The MAC covers keys and values as well as their ordering.

https://fluxcd.io/docs/guides/mozilla-sops/

brew install gnupg sops

Copy .sops.yaml from the root to the client.

Import public key: gpg --import gpg-public.asc
Import private key: gpg --import gpg-private.asc

Encrypt file:
sops --encrypt --in-place YOUR_SECRET.yaml

In case of MAC mismatch:
sops --ignore-mac YOUR_SECRET.yaml
