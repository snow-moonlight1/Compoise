import React, { useEffect, useState } from 'react';
import { XIcon } from '../Icons';

export interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: string;
  hideClose?: boolean;
}

export const Modal: React.FC<ModalProps> = ({ isOpen, onClose, children, title, hideClose = false }) => {
  const [shouldRender, setShouldRender] = useState(isOpen);
  const [isAnimating, setIsAnimating] = useState(isOpen);

  useEffect(() => {
    if (isOpen) {
      setShouldRender(true);
      // Use double requestAnimationFrame or small timeout to ensure browser paints before applying 'in' class if we were transitioning styles.
      // But with keyframe animations on mount, it works immediately.
      setIsAnimating(true);
    } else {
      setIsAnimating(false);
      const timer = setTimeout(() => {
        setShouldRender(false);
      }, 300); // Match animation duration
      return () => clearTimeout(timer);
    }
  }, [isOpen]);

  if (!shouldRender) return null;

  return (
    <div 
      className={`fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm ${isAnimating ? 'animate-fade-in' : 'animate-fade-out'}`}
    >
      <div 
        className={`neu-flat dark:text-slate-200 rounded-2xl w-full max-w-md p-6 relative overflow-hidden max-h-[90vh] flex flex-col shadow-2xl ${isAnimating ? 'animate-slide-up' : 'animate-slide-out'}`}
      >
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