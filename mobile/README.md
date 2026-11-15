# Keshav Dairy KhataBook – Android

Flutter Android scaffold for Keshav Dairy & Beverages. It currently contains a
home placeholder, navigation shell, API foundation, and tests. Customer and Khata
screens will be implemented in later approved steps.

## Android emulator

Start the Django API on port 8000, then run `flutter run` from this directory.
The emulator base URL is `http://10.0.2.2:8000/api/`.

## Physical Android device

Connect the phone and computer to a network where the phone can reach the
computer. Replace the sample address with the computer's LAN IP:

```powershell
flutter run --dart-define=KHATABOOK_API_TARGET=physical --dart-define=KHATABOOK_PHYSICAL_DEVICE_API_URL=http://192.168.1.20:8000/api
```

Django must listen on an address reachable on the LAN, and its allowed-host
configuration must include the computer's LAN address. This setup does not edit
backend settings. Use HTTPS outside local development.

## API and authentication foundation

`lib/core/network/api_client.dart` provides reusable JSON GET/POST requests,
optional bearer-token attachment, and optional `Idempotency-Key` support.
JWT login uses `POST /api/auth/token/`, refresh uses
`POST /api/auth/token/refresh/`, and logout uses `POST /api/auth/logout/`.
The app stores the access/refresh pair with Android secure storage. Login uses
the Django username and password but does not save the password. Access tokens
are short-lived; failed authenticated requests share a single refresh operation
and are retried at most once.

Run checks with `flutter analyze` and `flutter test`.
