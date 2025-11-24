import React from 'react';
import { XIcon } from '../Icons';

export interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: string;
  hideClose?: boolean;
}

export const Modal: React.FC<ModalProps> = ({ isOpen, onClose, children, title, hideClose = false }) => {
  if (!isOpen) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm animate-fade-in">
      <div className="neu-flat dark:text-slate-200 rounded-2xl w-full max-w-md p-6 relative animate-slide-up overflow-hidden max-h-[90vh] flex flex-col shadow-2xl">
        <div className="flex justify-between items-center mb-4 flex-none">
          {title && <h2 className="text-xl font-bold text-slate-800 dark:text-white">{title}</h2>}
          {!hideClose && (
            <button onClick={onClose} className="neu-btn p-2 rounded-full text-slate-500 hover:text-slate-700 dark:hover:text-slate-300 transition-colors absolute top-4 right-4">
              <XIcon size={18} />
            </button>
          )}
        </div>
        <div className="flex-1 overflow-y-auto custom-scrollbar pr-2">
          {children}
        </div>
      </div>
    </div>
  );
};