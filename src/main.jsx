import React from 'react';
import { createRoot } from 'react-dom/client';
import './index.css';
import { App, ErrorBoundary } from './app.jsx';

document.getElementById('boot')?.remove();
createRoot(document.getElementById('root')).render(
  React.createElement(ErrorBoundary, null, React.createElement(App))
);
