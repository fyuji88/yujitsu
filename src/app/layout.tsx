import type { Metadata, Viewport } from 'next';
import './globals.css';
import { SCRIPT_TEMA } from '@/lib/tema';

export const metadata: Metadata = {
  title: 'yujitsu',
  description: 'Diario de rolls y análisis de juego',
  manifest: '/manifest.webmanifest',
  appleWebApp: { capable: true, statusBarStyle: 'default', title: 'yujitsu' },
};

export const viewport: Viewport = {
  /* El hueso de Gullo: el tema por defecto es el claro. Cuando el usuario
     elige oscuro, `aplicarTema()` reescribe esta meta en caliente para que la
     barra del sistema no se quede del color contrario. */
  themeColor: '#f1f0ee',
  viewportFit: 'cover',
  width: 'device-width',
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    /* `suppressHydrationWarning` porque el script de abajo escribe
       `data-tema` en <html> antes de que React hidrate: el servidor no puede
       saber qué tema eligió este usuario. Es la única diferencia esperada
       entre el HTML del servidor y el del cliente. */
    <html lang="es" suppressHydrationWarning>
      <head>
        {/* Antes de pintar nada. Si esto esperase a React, la app abriría en
            claro y saltaría a oscuro delante del usuario — un fogonazo blanco
            en un gimnasio a oscuras. */}
        <script dangerouslySetInnerHTML={{ __html: SCRIPT_TEMA }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
