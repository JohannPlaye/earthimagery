'use client';

import React, { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';

interface LoginModalProps {
  open: boolean;
  onClose: () => void;
  onSuccess?: () => void;
}

export default function LoginModal({ open, onClose, onSuccess }: LoginModalProps) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const { login } = useAuth();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setIsLoading(true);

    try {
      const success = await login(username, password);
      
      if (success) {
        setUsername('');
        setPassword('');
        onSuccess?.();
        onClose();
      } else {
        setError('Identifiants invalides');
      }
    } catch (error) {
      setError('Erreur de connexion');
      console.error('Erreur de connexion:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleClose = () => {
    if (!isLoading) {
      setUsername('');
      setPassword('');
      setError('');
      onClose();
    }
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-12">
      {/* Background semi-transparent avec blur fort */}
      <div 
        className="absolute inset-0 backdrop-blur-md" 
        style={{ backgroundColor: 'rgba(0, 0, 0, 0.5)' }}
        onClick={handleClose} 
      />
      
      {/* Modal avec transparence interne */}
      <div className="relative rounded-xl border border-purple-700 shadow-2xl w-full max-w-md overflow-hidden" style={{ background: 'rgba(35, 35, 54, 0.7)' }}>
        <button
          className="absolute top-4 right-4 text-gray-400 hover:text-purple-400 text-xl z-10"
          onClick={handleClose}
          title="Fermer"
        >
          &times;
        </button>
        
        <div className="p-8">
          {/* Titre */}
          <div className="mb-6 text-center">
            <div className="text-4xl mb-2">🔐</div>
            <h2 className="text-xl font-semibold text-purple-300">Authentification requise</h2>
            <p className="text-sm text-gray-400 mt-1">Connectez-vous pour accéder aux datasets</p>
          </div>

          {/* Formulaire */}
          <form onSubmit={handleSubmit} className="space-y-4">
            {error && (
              <div className="p-3 rounded-lg bg-red-900/30 border border-red-700 text-red-300 text-sm text-center">
                {error}
              </div>
            )}
            
            <div className="space-y-2">
              <label className="block text-sm text-gray-300">Nom d&apos;utilisateur</label>
              <input
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                disabled={isLoading}
                className="w-full px-3 py-2 bg-[#232336] border border-[#2d2d44] rounded-lg text-white focus:border-purple-400 focus:outline-none disabled:opacity-50"
                placeholder="Entrez votre nom d'utilisateur"
              />
            </div>
            
            <div className="space-y-2">
              <label className="block text-sm text-gray-300">Mot de passe</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={isLoading}
                className="w-full px-3 py-2 bg-[#232336] border border-[#2d2d44] rounded-lg text-white focus:border-purple-400 focus:outline-none disabled:opacity-50"
                placeholder="Entrez votre mot de passe"
              />
            </div>

            <div className="flex gap-3 pt-4">
              <button
                type="button"
                onClick={handleClose}
                disabled={isLoading}
                className="flex-1 px-4 py-2 text-gray-300 border border-gray-600 rounded-lg hover:bg-gray-700/50 disabled:opacity-50 transition-colors"
              >
                Annuler
              </button>
              <button
                type="submit"
                disabled={isLoading || !username || !password}
                className="flex-1 px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 disabled:opacity-50 disabled:bg-gray-600 transition-colors flex items-center justify-center gap-2"
              >
                {isLoading && (
                  <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></div>
                )}
                {isLoading ? 'Connexion...' : 'Se connecter'}
              </button>
            </div>
          </form>

          {/* Informations d'aide */}
          <div className="mt-6 p-3 bg-[#232336]/50 border border-[#2d2d44] rounded-lg">
            <div className="text-sm text-gray-400 mb-2">
              <strong className="text-purple-300">Visualisation simple des datasets :</strong>
            </div>
            <div className="text-xs text-gray-500 space-y-1">
              <div>• <strong className="text-white">viewer</strong> / <strong className="text-white">viewer</strong></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
