import type { Metadata, Viewport } from 'next';
import './globals.css';
import { SCRIPT_TEMA } from '@/lib/tema';

export const metadata: Metadata = {
  title: 'yujitsu',
  description: 'Diario de rolls y análisis de juego',
  manifest: '/manifest.webmanifest',
  appleWebApp: { capable: true, statusBarStyle: 'default', title: 'yujitsu' },
  /* iOS ignora el manifest para el icono de la pantalla de inicio: se lo tiene
     que decir el `apple-touch-icon`. Y lo quiere con fondo, no transparente,
     porque no le pone ninguno detrás. */
  icons: {
    icon: [
      { url: '/icon-192.png', sizes: '192x192', type: 'image/png' },
      { url: '/icon-512.png', sizes: '512x512', type: 'image/png' },
    ],
    apple: [{ url: '/apple-touch-icon.png', sizes: '180x180', type: 'image/png' }],
  },
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
