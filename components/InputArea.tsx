import React from 'react';
import { InputMode } from '../types';
import { LoaderIcon, SparklesIcon, PlusIcon } from './Icons';

interface InputAreaProps {
  inputMode: InputMode;
  setInputMode: (mode: InputMode) => void;
  inputText: string;
  setInputText: (text: string) => void;
  handleAISort: () => void;
  handleManualAdd: () => void;
  isProcessing: boolean;
  t: any;
}

export const InputArea: React.FC<InputAreaProps> = ({
  inputMode,
  setInputMode,
  inputText,
  setInputText,
  handleAISort,
  handleManualAdd,
  isProcessing,
  t
}) => (
  <div className="flex flex-col h-full">
    <div className="flex p-1 bg-slate-200 dark:bg-slate-800 rounded-xl mb-4">
      <button 
        onClick={() => setInputMode('single')}
        className={`flex-1 py-2 text-sm font-bold rounded-lg transition-all duration-200 ${inputMode === 'single' ? 'neu-btn bg-bgLight dark:bg-bgDark text-slate-800 dark:text-slate-100 scale-100' : 'text-slate-500 hover:text-slate-400 scale-95'}`}
      >
        {t.modeManual}
      </button>
      <button 
        onClick={() => setInputMode('brainDump')}
        className={`flex-1 py-2 text-sm font-bold rounded-lg transition-all duration-200 ${inputMode === 'brainDump' ? 'neu-btn bg-bgLight dark:bg-bgDark text-slate-800 dark:text-slate-100 scale-100' : 'text-slate-500 hover:text-slate-400 scale-95'}`}
      >
        {t.modeAI}
      </button>
    </div>

    <textarea 
      value={inputText}
      onChange={(e) => setInputText(e.target.value)}
      placeholder={inputMode === 'brainDump' ? t.inputPlaceholderAI : t.inputPlaceholderManual}
      className="w-full flex-1 neu-pressed rounded-xl p-4 bg-transparent border-none focus:outline-none text-slate-700 dark:text-slate-200 placeholder-slate-400 resize-none min-h-[120px]"
      onKeyDown={(e) => {
        if (e.key === 'Enter' && e.metaKey) {
          inputMode === 'brainDump' ? handleAISort() : handleManualAdd();
        }
      }}
    />
    
    {inputMode === 'brainDump' && (
       <p className="text-xs text-slate-500 mt-2 text-center">{t.aiNote}</p>
    )}

    <div className="mt-4 flex justify-end">
      {inputMode === 'brainDump' ? (
        <button 
          onClick={handleAISort}
          disabled={isProcessing || !inputText.trim()}
          className="neu-btn w-full py-3 rounded-xl font-bold text-primary hover:opacity-80 disabled:opacity-50 flex justify-center items-center gap-2 active:scale-95 transition-transform"
        >
          {isProcessing ? <LoaderIcon className="animate-spin" /> : <SparklesIcon />}
          {t.analyzeBtn}
        </button>
      ) : (
         <button 
          onClick={handleManualAdd}
          disabled={!inputText.trim()}
          className="neu-btn w-full py-3 rounded-xl font-bold text-primary hover:opacity-80 flex justify-center items-center gap-2 active:scale-95 transition-transform"
        >
          <PlusIcon />
          {t.addSingleBtn}
        </button>
      )}
    </div>

    <div className="mt-auto pt-6 text-center">
       <div className="flex items-center justify-center gap-2 mb-1 text-slate-400">
          <span className="font-bold text-sm tracking-wider opacity-70">MatrixFlow AI</span>
       </div>
       <p className="text-[10px] text-slate-400 font-medium">
          &copy; {new Date().getFullYear()}
       </p>
    </div>
  </div>
);