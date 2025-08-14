import { NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'votre-secret-jwt-changez-moi-en-production';

export async function GET() {
  try {
    const cookieStore = await cookies();
    const token = cookieStore.get('auth-token')?.value;

    if (!token) {
      return NextResponse.json({ authenticated: false });
    }

    try {
      const decoded = jwt.verify(token, JWT_SECRET) as {
        userId: string;
        username: string;
        role: string;
        permissions: string[];
      };

      return NextResponse.json({
        authenticated: true,
        user: {
          id: decoded.userId,
          username: decoded.username,
          role: decoded.role,
          permissions: decoded.permissions
        }
      });
    } catch (jwtError) {
      // Token invalide
      cookieStore.delete('auth-token');
      return NextResponse.json({ authenticated: false });
    }

  } catch (error) {
    console.error('Erreur lors de la vérification:', error);
    return NextResponse.json(
      { error: 'Erreur interne du serveur' },
      { status: 500 }
    );
  }
}
