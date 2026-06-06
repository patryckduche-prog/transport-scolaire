# Firebase Admin

Place the Firebase Admin service account here:

```text
backend/config/firebase-service-account.json
```

The file is ignored by Git and by default must not be shared publicly.

Then set in `backend/.env`:

```text
FCM_SERVICE_ACCOUNT_PATH=./config/firebase-service-account.json
```
