### 🪝 Github Webhook

Flux is pull-based by design meaning it will periodically check your git repository for changes, using a webhook you can enable Flux to update your cluster on `git push`. In order to configure Github to send `push` events from your repository to the Flux webhook receiver you will need two things:

1. Webhook URL - Your webhook receiver will be deployed on `https://flux-webhook.privatedomain.com/hook/:hookId`. In order to find out your hook id you can run the following command:

    ```sh
    kubectl -n flux-system get receiver/github-receiver
    # NAME              AGE    READY   STATUS
    # github-receiver   6h8m   True    Receiver initialized with URL: /hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
    ```

    The full url would look like this:

    ```text
    https://flux-webhook.privatedomain.com/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
    ```

2. Webhook secret - Webhook secret is stored in `github-webhook-token` external secret.

Set everything up on the Github repository side. Navigate to the settings of your repository on Github, under "Settings/Webhooks" press the "Add webhook" button. Fill in the webhook url and secret.
