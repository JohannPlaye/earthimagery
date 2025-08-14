# Système d'authentification EarthImagery

## Vue d'ensemble

Le système d'authentification protège l'accès à l'onglet "Datasets" et aux fonctionnalités de gestion des datasets. Il utilise :

- **Fichiers JSON** pour la gestion des utilisateurs
- **JWT tokens** pour les sessions
- **bcrypt** pour le hachage des mots de passe
- **Permissions granulaires** pour contrôler l'accès

## Structure des fichiers

```
config/
├── users.json           # Configuration des utilisateurs
└── download-tracking.json

src/
├── lib/
│   ├── auth.ts          # Fonctions d'authentification serveur
│   └── auth-middleware.ts # Middleware de protection des routes
├── contexts/
│   └── AuthContext.tsx  # Contexte React pour l'authentification
├── components/
│   └── LoginModal.tsx   # Modal de connexion
└── app/api/auth/
    ├── login/route.ts   # Endpoint de connexion
    ├── logout/route.ts  # Endpoint de déconnexion
    └── me/route.ts      # Vérification du statut de connexion

scripts/
└── hash-password.js     # Utilitaire pour générer des mots de passe
```

## Configuration des utilisateurs

Le fichier `config/users.json` contient :

```json
{
  "users": [
    {
      "id": "admin",
      "username": "admin",
      "password": "$2b$10$...", // Hash bcrypt
      "role": "admin",
      "permissions": ["dataset_manage", "dataset_view"]
    }
  ],
  "config": {
    "session_duration_hours": 24,
    "require_auth_for": ["dataset_manage", "dataset_view"]
  }
}
```

### Rôles et permissions

- **`dataset_view`** : Permet de voir l'onglet datasets (lecture seule)
- **`dataset_manage`** : Permet de gérer les datasets (enable/disable, validation, etc.)

### Rôles prédéfinis

- **`admin`** : Accès complet (dataset_view + dataset_manage)
- **`viewer`** : Lecture seule (dataset_view uniquement)

## Utilisation

### Comptes de test

Par défaut, deux comptes sont configurés :
- **admin/admin** : Accès administrateur complet
- **viewer/viewer** : Accès lecture seule

### Générer un nouveau mot de passe

```bash
node scripts/hash-password.js monMotDePasse123
```

### Ajouter un nouvel utilisateur

1. Générez le hash du mot de passe
2. Ajoutez l'utilisateur dans `config/users.json`
3. Redémarrez l'application

Exemple :
```json
{
  "id": "newuser",
  "username": "newuser",
  "password": "$2b$10$hash_généré...",
  "role": "viewer",
  "permissions": ["dataset_view"]
}
```

## Sécurité

### Variables d'environnement

Ajoutez dans `.env.local` :
```bash
JWT_SECRET=votre-secret-jwt-super-securise-changez-moi
```

### Points de protection

1. **Frontend** : L'onglet Dataset affiche un message de connexion si non authentifié
2. **API Routes** : Les endpoints sensibles vérifient les permissions
3. **Sessions** : Les tokens JWT expirent après 24h

### Routes protégées

- `/api/datasets/toggle` : Requiert `dataset_manage`
- `/api/datasets/validate` : Requiert `dataset_manage`

### Routes publiques

- `/api/datasets/status` : Accessible à tous (données publiques)
- `/api/datasets/images` : Accessible à tous (données publiques)

## Personnalisation

### Modifier la durée des sessions

Dans `config/users.json` :
```json
{
  "config": {
    "session_duration_hours": 48
  }
}
```

### Ajouter de nouvelles permissions

1. Définissez la permission dans le fichier utilisateur
2. Ajoutez la vérification dans les composants/routes concernés
3. Utilisez `hasPermission(user, 'nouvelle_permission')`

### Changer le style du modal de connexion

Modifiez `src/components/LoginModal.tsx` - les styles utilisent Material-UI avec un thème sombre personnalisé.

## Dépannage

### "Identifiants invalides"
- Vérifiez que l'utilisateur existe dans `config/users.json`
- Vérifiez que le mot de passe correspond (en mode développement, les mots de passe en clair "admin" et "viewer" sont acceptés)

### "Accès non autorisé"
- Vérifiez que l'utilisateur a les bonnes permissions
- Vérifiez que le token JWT n'a pas expiré

### Problèmes de cookies
- Vérifiez que le domaine/port correspondent
- En développement, les cookies sécurisés sont désactivés

## Migration vers la production

1. **Changez le JWT_SECRET** dans les variables d'environnement
2. **Supprimez les comptes de test** ou changez leurs mots de passe
3. **Activez HTTPS** pour la sécurité des cookies
4. **Configurez des mots de passe forts** pour tous les comptes
