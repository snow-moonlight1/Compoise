
import React, { useEffect } from 'react';
import { AlertTriangleIcon } from '../Icons';

export type ToastType = 'error' | 'success';

export interface ToastItem {
  id: number;
  message: string;
  type: ToastType;
}

const TOAST_DURATION_MS = 3500;

const Toast: React.FC<{ item: ToastItem; onDismiss: (id: number) => void }> = ({ item, onDismiss }) => {
  useEffect(() => {
    const timer = setTimeout(() => onDismiss(item.id), TOAST_DURATION_MS);
    return () => clearTimeout(timer);
  }, [item.id, onDismiss]);

  return (
    <div
      role="status"
      className={`animate-slide-up pointer-events-auto flex items-center gap-2 rounded-xl px-4 py-3 text-sm font-bold shadow-lg max-w-sm ${
        item.type === 'error'
          ? 'bg-red-500 text-white shadow-red-500/30'
          : 'bg-emerald-500 text-white shadow-emerald-500/30'
      }`}
    >
      {item.type === 'error' ? (
        <AlertTriangleIcon size={16} className="flex-none" />
      ) : (
        <svg className="w-4 h-4 flex-none" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={3}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
        </svg>
      )}
      <span className="break-words">{item.message}</span>
      <button
        onClick={() => onDismiss(item.id)}
        aria-label="×"
        className="ml-1 opacity-70 hover:opacity-100 flex-none"
      >
        <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={3}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M18 6 6 18M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
};

export const ToastStack: React.FC<{ toasts: ToastItem[]; onDismiss: (id: number) => void }> = ({ toasts, onDismiss }) => {
  if (toasts.length === 0) return null;
  return (
    <div className="fixed top-4 left-1/2 -translate-x-1/2 z-[70] flex flex-col items-center gap-2 pointer-events-none">
      {toasts.map(item => (
        <Toast key={item.id} item={item} onDismiss={onDismiss} />
      ))}
    </div>
  );
};
