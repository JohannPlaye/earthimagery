#!/usr/bin/env node

/**
 * Script pour générer des mots de passe hashés pour l'authentification
 * Usage: node scripts/hash-password.js [password]
 */

const bcrypt = require('bcryptjs');

async function hashPassword(password) {
  try {
    const hash = await bcrypt.hash(password, 10);
    console.log(`Mot de passe: ${password}`);
    console.log(`Hash: ${hash}`);
    console.log('');
    console.log('Ajoutez ce hash au fichier config/users.json');
  } catch (error) {
    console.error('Erreur lors du hachage:', error);
  }
}

const password = process.argv[2];

if (!password) {
  console.log('Usage: node scripts/hash-password.js [password]');
  console.log('');
  console.log('Exemples:');
  console.log('  node scripts/hash-password.js admin');
  console.log('  node scripts/hash-password.js monMotDePasse123');
  process.exit(1);
}

hashPassword(password);
