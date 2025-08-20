Le contenu de cette page est la réplication de la page :
https://api.eumetsat.int/api-key/

# Api Key Management
Les identifiants / pass pour se loger sur cette page sont stockés dans le trousseau iCloud.
## User credentials
### Consumer key
```bash
1hK2fINugbeWv6T7UA9Uqk4PAoEa
```
### Consumer secret
```bash
0_i8fkJR8knY6xDNh9IqWIavy30a
```

It is possible to generate an API access token by calling the token API service using the credentials provided above. Below the cURL command:

```bash
curl -k -d "grant_type=client_credentials" \
-H "Authorization: Basic MWhLMmZJTnVnYmVXdjZUN1VBOVVxazRQQW9FYTowX2k4ZmtKUjhrblk2eEROaDlJcVdJYXZ5MzBh" \
https://api.eumetsat.int/token
```

## API Token
The following token can be used to access the APIs. It has a validity of one hour
### API token
```bash
44310692-c938-3526-a633-21208fe32351
```

It should be added in the http header of each API call as shown in the following sample cURL command:

```bash
curl -k \
-H "Authorization: Bearer 44310692-c938-3526-a633-21208fe32351" \
<api-endpoint>
```