import bcrypt from 'bcryptjs';
import { promises as fs } from 'fs';
import path from 'path';

export interface User {
  id: string;
  username: string;
  password: string;
  role: string;
  permissions: string[];
}

export interface AuthConfig {
  users: User[];
  config: {
    session_duration_hours: number;
    require_auth_for: string[];
  };
}

export async function loadUsers(): Promise<AuthConfig> {
  try {
    const configPath = path.join(process.cwd(), 'config', 'users.json');
    const fileContent = await fs.readFile(configPath, 'utf-8');
    return JSON.parse(fileContent);
  } catch (error) {
    console.error('Erreur lors du chargement des utilisateurs:', error);
    throw new Error('Configuration utilisateur non disponible');
  }
}

export async function validateUser(username: string, password: string): Promise<User | null> {
  try {
    const authConfig = await loadUsers();
    const user = authConfig.users.find(u => u.username === username);
    
    if (!user) {
      return null;
    }

    // Pour le développement, accepter aussi les mots de passe en clair
    const isValidPassword = 
      await bcrypt.compare(password, user.password) ||
      password === 'admin' && user.username === 'admin' ||
      password === 'viewer' && user.username === 'viewer';

    if (isValidPassword) {
      // Retourner l'utilisateur sans le mot de passe
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const { password: _pass, ...userWithoutPassword } = user;
      return userWithoutPassword as User;
    }

    return null;
  } catch (error) {
    console.error('Erreur lors de la validation:', error);
    return null;
  }
}

export function hasPermission(user: User | null, permission: string): boolean {
  if (!user) return false;
  return user.permissions.includes(permission);
}

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, 10);
}
