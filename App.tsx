
import React, { useState, useEffect } from 'react';
import { Task, QuadrantType, AIConfig, AIProvider, AppSettings, InputMode, Board, ThemeColor } from './types';
import { analyzeTasks, decomposeTask } from './services/aiService';
import { translations } from './translations';
import { 
  SparklesIcon, SettingsIcon, PlusIcon, XIcon, 
  AlertTriangleIcon, LoaderIcon, SplitIcon, TrashIcon,
  MoonIcon, SunIcon, GlobeIcon, MonitorIcon
} from './components/Icons';

// --- Interfaces ---

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: string;
}

interface TaskCardProps {
  task: Task;
  onDragStart: (e: React.DragEvent, task: Task) => void;
  onDelete: (id: string) => void;
  onDecompose: (task: Task) => void;
  colors: { border: string, text: string };
}

interface QuadrantProps {
  type: QuadrantType;
  title: string;
  shortTitle: string;
  colorCode: string; // Tailwind color class mapping
  tasks: Task[];
  onDrop: (e: React.DragEvent, quadrant: QuadrantType) => void;
  onDragOver: (e: React.DragEvent) => void;
  onDragStart: (e: React.DragEvent, task: Task) => void;
  onDelete: (id: string) => void;
  onDecompose: (task: Task) => void;
  t: any;
}

// --- Components ---

const Modal: React.FC<ModalProps> = ({ isOpen, onClose, children, title }) => {
  if (!isOpen) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm animate-fade-in">
      <div className="neu-flat dark:text-slate-200 rounded-2xl w-full max-w-md p-6 relative animate-slide-up overflow-hidden">
        <div className="flex justify-between items-center mb-4">
          {title && <h2 className="text-xl font-bold">{title}</h2>}
          <button onClick={onClose} className="neu-btn p-2 rounded-full text-slate-500 hover:text-slate-700 dark:hover:text-slate-300 transition-colors absolute top-4 right-4">
            <XIcon size={18} />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
};

const TaskCard: React.FC<TaskCardProps> = ({ 
  task, 
  onDragStart, 
  onDelete, 
  onDecompose,
  colors
}) => {
  return (
    <div
      draggable
      onDragStart={(e) => onDragStart(e, task)}
      className="neu-btn p-3 mb-3 rounded-xl cursor-grab active:cursor-grabbing group relative overflow-hidden flex justify-between items-start gap-2"
    >
      {task.isLongTerm && (
        <div className="absolute top-0 left-0 w-1 h-full bg-yellow-400/50" />
      )}
      
      <div className="flex-1 min-w-0">
         <p className="text-sm font-bold text-slate-700 dark:text-slate-200 break-words leading-tight">
          {task.title}
         </p>
      </div>

      <div className="flex flex-col gap-2 opacity-60 hover:opacity-100 transition-opacity">
        {task.isLongTerm && (
           <button 
             onClick={(e) => { e.stopPropagation(); onDecompose(task); }}
             className="text-yellow-500 hover:scale-110 transition-transform"
             title="Decompose"
           >
             <SplitIcon size={14} />
           </button>
        )}
        <button 
          onClick={(e) => { e.stopPropagation(); onDelete(task.id); }}
          className="text-red-400 hover:scale-110 transition-transform"
          title="Delete"
        >
          <TrashIcon size={14} />
        </button>
      </div>
    </div>
  );
};

const Quadrant: React.FC<QuadrantProps> = ({ 
  type, 
  title, 
  shortTitle,
  colorCode, 
  tasks, 
  onDrop, 
  onDragOver, 
  onDragStart,
  onDelete,
  onDecompose,
  t
}) => {
  // Mapping tailwind colors for borders/text
  const getColorStyles = (code: string) => {
    switch(code) {
      case 'q1': return { border: 'border-q1', text: 'text-q1' };
      case 'q2': return { border: 'border-q2', text: 'text-q2' };
      case 'q3': return { border: 'border-q3', text: 'text-q3' };
      case 'q4': return { border: 'border-q4', text: 'text-q4' };
      default: return { border: 'border-slate-400', text: 'text-slate-400' };
    }
  };
  
  const styles = getColorStyles(colorCode);

  return (
    <div 
      onDrop={(e) => onDrop(e, type)}
      onDragOver={onDragOver}
      className="neu-pressed rounded-2xl flex flex-col h-full overflow-hidden relative"
    >
      <div className={`p-3 flex justify-between items-center border-b border-slate-200/10`}>
        <div className="flex items-center gap-2">
          <div className={`w-2 h-2 rounded-full bg-${colorCode}`}></div>
          <h3 className="font-bold text-slate-600 dark:text-slate-300 text-sm md:text-base truncate hidden md:block">{title}</h3>
          <h3 className="font-bold text-slate-600 dark:text-slate-300 text-sm md:text-base truncate block md:hidden">{shortTitle}</h3>
        </div>
        <span className="text-xs font-bold text-slate-400 bg-slate-200/50 dark:bg-slate-700/50 px-2 py-0.5 rounded-full">
          {tasks.length}
        </span>
      </div>
      
      <div className="flex-1 p-2 overflow-y-auto custom-scrollbar">
        {tasks.length === 0 ? (
          <div className="h-full flex items-center justify-center text-slate-400 text-xs italic select-none">
            {t.empty}
          </div>
        ) : (
          tasks.map(task => (
            <TaskCard 
              key={task.id} 
              task={task} 
              onDragStart={onDragStart} 
              onDelete={onDelete}
              onDecompose={onDecompose}
              colors={styles}
            />
          ))
        )}
      </div>
    </div>
  );
};

// --- Main App ---

export default function App() {
  // --- State ---
  const [boards, setBoards] = useState<Board[]>([]);
  const [activeBoardId, setActiveBoardId] = useState<string>('');
  const [tasks, setTasks] = useState<Task[]>([]);
  
  // UI State
  const [inputMode, setInputMode] = useState<InputMode>('single');
  const [inputText, setInputText] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [addModalOpen, setAddModalOpen] = useState(false);
  const [boardMenuOpen, setBoardMenuOpen] = useState(false);
  const [renameBoardId, setRenameBoardId] = useState<string | null>(null);
  const [newBoardName, setNewBoardName] = useState('');
  
  // Decompose State
  const [decomposeTaskItem, setDecomposeTaskItem] = useState<Task | null>(null);
  const [isDecomposing, setIsDecomposing] = useState(false);

  // Config & Settings State
  const [aiConfig, setAiConfig] = useState<AIConfig>({
    provider: AIProvider.Gemini,
    customBaseUrl: '',
    customApiKey: '',
    customModel: 'gpt-4o-mini'
  });

  const [appSettings, setAppSettings] = useState<AppSettings>({
    language: 'en',
    theme: 'system',
    themeColor: 'blue',
    defaultInputMode: 'single'
  });

  // Helper for translations
  const t = translations[appSettings.language];

  // --- Effects ---

  // Load initial state & Migrate Data
  useEffect(() => {
    const savedConfig = localStorage.getItem('matrixflow-config');
    if (savedConfig) setAiConfig(JSON.parse(savedConfig));

    const savedSettings = localStorage.getItem('matrixflow-settings');
    if (savedSettings) {
      const parsed = JSON.parse(savedSettings);
      setAppSettings(parsed);
      setInputMode(parsed.defaultInputMode); 
    }

    // Board & Task Migration
    const savedBoards = localStorage.getItem('matrixflow-boards');
    const savedTasks = localStorage.getItem('matrixflow-tasks');
    
    let loadedBoards: Board[] = [];
    let loadedTasks: Task[] = [];

    if (savedBoards) {
      loadedBoards = JSON.parse(savedBoards);
    }
    
    if (savedTasks) {
      const rawTasks = JSON.parse(savedTasks);
      // Migration: If tasks exist but don't have boardId, assign them to a default board
      if (rawTasks.length > 0 && !rawTasks[0].boardId) {
        const defaultBoardId = crypto.randomUUID();
        if (loadedBoards.length === 0) {
          loadedBoards.push({ id: defaultBoardId, name: t.defaultBoardName, createdAt: Date.now() });
        } else {
            // Use first existing board if available
        }
        const targetBoardId = loadedBoards[0]?.id || defaultBoardId;
        loadedTasks = rawTasks.map((task: any) => ({ ...task, boardId: targetBoardId }));
      } else {
        loadedTasks = rawTasks;
      }
    }

    // If no boards at all (fresh install or after migration), create one
    if (loadedBoards.length === 0) {
      const newBoard = { id: crypto.randomUUID(), name: t.defaultBoardName, createdAt: Date.now() };
      loadedBoards.push(newBoard);
    }

    setBoards(loadedBoards);
    setTasks(loadedTasks);
    setActiveBoardId(loadedBoards[0].id);

  }, []);

  // Save changes
  useEffect(() => { if (tasks.length > 0) localStorage.setItem('matrixflow-tasks', JSON.stringify(tasks)); }, [tasks]);
  useEffect(() => { if (boards.length > 0) localStorage.setItem('matrixflow-boards', JSON.stringify(boards)); }, [boards]);
  useEffect(() => { localStorage.setItem('matrixflow-config', JSON.stringify(aiConfig)); }, [aiConfig]);
  useEffect(() => { localStorage.setItem('matrixflow-settings', JSON.stringify(appSettings)); }, [appSettings]);

  // Theme & Color Handling
  useEffect(() => {
    const root = window.document.documentElement;
    root.classList.remove('light', 'dark');
    
    // Set Mode
    if (appSettings.theme === 'system') {
      if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
        root.classList.add('dark');
      } else {
        root.classList.add('light');
      }
    } else {
      root.classList.add(appSettings.theme);
    }

    // Set Color Theme Variable
    const colorMap: Record<ThemeColor, string> = {
      blue: '#3b82f6',
      purple: '#8b5cf6',
      green: '#10b981',
      orange: '#f97316',
      pink: '#ec4899'
    };
    root.style.setProperty('--primary', colorMap[appSettings.themeColor] || '#3b82f6');

  }, [appSettings.theme, appSettings.themeColor]);

  // --- Handlers ---

  const activeTasks = tasks.filter(t => t.boardId === activeBoardId);
  const activeBoard = boards.find(b => b.id === activeBoardId);

  const openAddModal = () => {
    setInputMode(appSettings.defaultInputMode);
    setAddModalOpen(true);
  };

  const handleDragStart = (e: React.DragEvent, task: Task) => {
    e.dataTransfer.setData('taskId', task.id);
    e.dataTransfer.effectAllowed = 'move';
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
  };

  const handleDrop = (e: React.DragEvent, targetQuadrant: QuadrantType) => {
    e.preventDefault();
    const taskId = e.dataTransfer.getData('taskId');
    setTasks(prev => prev.map(t => 
      t.id === taskId ? { ...t, quadrant: targetQuadrant } : t
    ));
  };

  const handleAISort = async () => {
    if (!inputText.trim()) return;
    
    setIsProcessing(true);
    try {
      const rawTasks = inputText.split('\n').filter(t => t.trim().length > 0);
      const results = await analyzeTasks(rawTasks, aiConfig, appSettings.language);
      
      const newTasks: Task[] = results.map(res => ({
        id: crypto.randomUUID(),
        boardId: activeBoardId,
        title: res.title,
        quadrant: res.quadrant,
        isLongTerm: res.isLongTerm,
        completed: false,
        createdAt: Date.now()
      }));
      
      // Append to TOP (LIFO)
      setTasks(prev => [...newTasks, ...prev]);
      setInputText('');
      
      if (addModalOpen) setAddModalOpen(false);

      const longTermTasks = newTasks.filter(t => t.isLongTerm);
      if (longTermTasks.length > 0) {
        setDecomposeTaskItem(longTermTasks[0]);
      }
      
    } catch (err) {
      alert(`${t.error}: ` + (err instanceof Error ? err.message : String(err)));
    } finally {
      setIsProcessing(false);
    }
  };

  const handleManualAdd = () => {
    if (!inputText.trim()) return;
    const newTask: Task = {
      id: crypto.randomUUID(),
      boardId: activeBoardId,
      title: inputText,
      quadrant: QuadrantType.Do, 
      isLongTerm: false,
      completed: false,
      createdAt: Date.now()
    };
    // Append to TOP (LIFO)
    setTasks(prev => [newTask, ...prev]);
    setInputText('');
    if (addModalOpen) setAddModalOpen(false);
  };

  const handleDecomposeConfirm = async () => {
    if (!decomposeTaskItem) return;
    setIsDecomposing(true);
    try {
      const subtasks = await decomposeTask(decomposeTaskItem.title, aiConfig, appSettings.language);
      const newTasks: Task[] = subtasks.map(st => ({
        id: crypto.randomUUID(),
        boardId: activeBoardId,
        title: st,
        quadrant: QuadrantType.Plan,
        isLongTerm: false,
        completed: false,
        createdAt: Date.now()
      }));

      setTasks(prev => {
        // Remove original if desired, or keep it. Currently replacing it logic could vary.
        // Here we just add subtasks. 
        // The existing code was: filter out old, add new. 
        // Let's keep it consistent but maybe keep the parent? No, user usually wants to break it down.
        const filtered = prev.filter(t => t.id !== decomposeTaskItem.id);
        return [...newTasks, ...filtered]; // Add new subtasks to TOP
      });
      
      setDecomposeTaskItem(null);
    } catch (err) {
      alert(t.error);
    } finally {
      setIsDecomposing(false);
    }
  };

  // Board Management Handlers
  const handleCreateBoard = () => {
    const newBoard: Board = {
      id: crypto.randomUUID(),
      name: t.untitledBoard,
      createdAt: Date.now()
    };
    setBoards(prev => [...prev, newBoard]);
    setActiveBoardId(newBoard.id);
    setRenameBoardId(newBoard.id);
    setNewBoardName(t.untitledBoard);
    setBoardMenuOpen(false);
  };

  const handleDeleteBoard = (id: string) => {
    if (boards.length <= 1) return; // Prevent deleting last board
    if (!confirm(t.confirmDeleteBoard)) return;
    
    setBoards(prev => prev.filter(b => b.id !== id));
    setTasks(prev => prev.filter(t => t.boardId !== id));
    
    if (activeBoardId === id) {
      const remaining = boards.filter(b => b.id !== id);
      if (remaining.length > 0) setActiveBoardId(remaining[0].id);
    }
  };

  const handleRenameBoard = () => {
    if (!newBoardName.trim() || !renameBoardId) return;
    setBoards(prev => prev.map(b => b.id === renameBoardId ? { ...b, name: newBoardName } : b));
    setRenameBoardId(null);
    setNewBoardName('');
  };

  // --- Renders ---

  const renderInputArea = (inModal = false) => (
    <div className="flex flex-col h-full">
      <div className="flex p-1 bg-slate-200 dark:bg-slate-800 rounded-xl mb-4">
        <button 
          onClick={() => setInputMode('single')}
          className={`flex-1 py-2 text-sm font-bold rounded-lg transition-all ${inputMode === 'single' ? 'neu-btn bg-bgLight dark:bg-bgDark text-slate-800 dark:text-slate-100' : 'text-slate-500 hover:text-slate-400'}`}
        >
          {t.modeManual}
        </button>
        <button 
          onClick={() => setInputMode('brainDump')}
          className={`flex-1 py-2 text-sm font-bold rounded-lg transition-all ${inputMode === 'brainDump' ? 'neu-btn bg-bgLight dark:bg-bgDark text-slate-800 dark:text-slate-100' : 'text-slate-500 hover:text-slate-400'}`}
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
            className="neu-btn w-full py-3 rounded-xl font-bold text-primary hover:opacity-80 disabled:opacity-50 flex justify-center items-center gap-2"
          >
            {isProcessing ? <LoaderIcon className="animate-spin" /> : <SparklesIcon />}
            {t.analyzeBtn}
          </button>
        ) : (
           <button 
            onClick={handleManualAdd}
            disabled={!inputText.trim()}
            className="neu-btn w-full py-3 rounded-xl font-bold text-primary hover:opacity-80 flex justify-center items-center gap-2"
          >
            <PlusIcon />
            {t.addSingleBtn}
          </button>
        )}
      </div>
    </div>
  );

  return (
    <div className="h-screen flex flex-col overflow-hidden selection:bg-primary selection:text-white font-sans">
      
      {/* --- Header --- */}
      <header className="flex-none h-16 flex items-center justify-between px-6 z-20 relative">
        <div className="flex items-center gap-3">
          <div className="neu-btn w-10 h-10 rounded-xl flex items-center justify-center text-primary">
             <span className="font-bold text-lg">M</span>
          </div>
          
          {/* Board Switcher */}
          <div className="relative">
             <button 
               onClick={() => setBoardMenuOpen(!boardMenuOpen)}
               className="flex items-center gap-2 font-bold text-lg text-slate-700 dark:text-slate-200 hover:text-primary transition-colors"
             >
               {activeBoard?.name || t.defaultBoardName}
               <svg className={`w-4 h-4 transition-transform ${boardMenuOpen ? 'rotate-180' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" /></svg>
             </button>

             {boardMenuOpen && (
               <div className="absolute top-full left-0 mt-2 w-64 neu-flat rounded-xl p-2 animate-fade-in z-50">
                 <div className="max-h-60 overflow-y-auto custom-scrollbar">
                   {boards.map(board => (
                     <div key={board.id} className="group flex items-center justify-between p-2 rounded-lg hover:bg-slate-200/50 dark:hover:bg-slate-700/50">
                        {renameBoardId === board.id ? (
                          <input 
                            autoFocus
                            value={newBoardName}
                            onChange={(e) => setNewBoardName(e.target.value)}
                            onBlur={handleRenameBoard}
                            onKeyDown={(e) => e.key === 'Enter' && handleRenameBoard()}
                            className="w-full bg-transparent text-sm font-bold outline-none"
                          />
                        ) : (
                          <button 
                            onClick={() => { setActiveBoardId(board.id); setBoardMenuOpen(false); }}
                            className={`flex-1 text-left text-sm font-bold truncate ${activeBoardId === board.id ? 'text-primary' : 'text-slate-600 dark:text-slate-300'}`}
                          >
                            {board.name}
                          </button>
                        )}
                        
                        <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button onClick={() => { setRenameBoardId(board.id); setNewBoardName(board.name); }} className="p-1 hover:text-primary"><SettingsIcon size={12}/></button>
                          {boards.length > 1 && (
                            <button onClick={() => handleDeleteBoard(board.id)} className="p-1 hover:text-red-500"><TrashIcon size={12}/></button>
                          )}
                        </div>
                     </div>
                   ))}
                 </div>
                 <div className="h-px bg-slate-300 dark:bg-slate-600 my-2"></div>
                 <button onClick={handleCreateBoard} className="w-full text-left p-2 text-sm font-bold text-primary hover:bg-slate-200/50 dark:hover:bg-slate-700/50 rounded-lg flex items-center gap-2">
                    <PlusIcon size={14} /> {t.createBoard}
                 </button>
               </div>
             )}
          </div>
        </div>
        
        <button 
          onClick={() => setSettingsOpen(true)}
          className="neu-btn p-3 rounded-full text-slate-500 dark:text-slate-400 hover:text-primary transition-colors"
        >
          <SettingsIcon />
        </button>
      </header>

      {/* --- Main Content --- */}
      <div className="flex-1 flex flex-col md:flex-row gap-6 px-4 md:px-8 pb-6 md:pb-8 overflow-hidden">
        
        {/* Desktop Input Panel (Hidden on Mobile) */}
        <div className="hidden md:block w-80 flex-none flex flex-col gap-4">
           <div className="neu-flat rounded-2xl p-6 flex-1">
              {renderInputArea()}
           </div>
           <div className="neu-flat rounded-2xl p-4 text-center text-xs text-slate-400">
             MatrixFlow AI &copy; 2024
           </div>
        </div>

        {/* The Matrix Grid */}
        <div className="flex-1 grid grid-cols-2 grid-rows-2 gap-3 md:gap-6 h-full">
          <Quadrant 
            type={QuadrantType.Do} 
            title={t.q1} shortTitle={t.q1Short} colorCode="q1"
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Do)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDelete={id => setTasks(prev => prev.filter(t => t.id !== id))}
            onDecompose={setDecomposeTaskItem}
            t={t}
          />
          <Quadrant 
            type={QuadrantType.Plan} 
            title={t.q2} shortTitle={t.q2Short} colorCode="q2"
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Plan)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDelete={id => setTasks(prev => prev.filter(t => t.id !== id))}
            onDecompose={setDecomposeTaskItem}
            t={t}
          />
          <Quadrant 
            type={QuadrantType.Delegate} 
            title={t.q3} shortTitle={t.q3Short} colorCode="q3"
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Delegate)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDelete={id => setTasks(prev => prev.filter(t => t.id !== id))}
            onDecompose={setDecomposeTaskItem}
            t={t}
          />
          <Quadrant 
            type={QuadrantType.Eliminate} 
            title={t.q4} shortTitle={t.q4Short} colorCode="q4"
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Eliminate)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDelete={id => setTasks(prev => prev.filter(t => t.id !== id))}
            onDecompose={setDecomposeTaskItem}
            t={t}
          />
        </div>

      </div>

      {/* Mobile FAB (Hidden on Desktop) */}
      <button 
        onClick={openAddModal}
        className="md:hidden absolute bottom-8 right-6 w-14 h-14 rounded-full bg-primary text-white shadow-lg shadow-primary/40 flex items-center justify-center active:scale-90 transition-transform z-30"
      >
        <PlusIcon size={28} />
      </button>

      {/* --- Modals --- */}

      {/* Mobile Add Task Modal */}
      <Modal isOpen={addModalOpen} onClose={() => setAddModalOpen(false)} title={t.addBtn}>
         {renderInputArea(true)}
      </Modal>

      {/* Settings Modal */}
      <Modal isOpen={settingsOpen} onClose={() => setSettingsOpen(false)} title={t.settings}>
        <div className="space-y-6 max-h-[60vh] overflow-y-auto custom-scrollbar pr-2">
          
          {/* Language Section */}
          <div>
            <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
               <GlobeIcon size={16} /> {t.language}
            </label>
            <div className="flex gap-2">
              {(['en', 'zh', 'ja'] as const).map(lang => (
                <button
                  key={lang}
                  onClick={() => setAppSettings(s => ({ ...s, language: lang }))}
                  className={`flex-1 py-2 rounded-lg text-sm font-bold transition-all ${appSettings.language === lang ? 'neu-pressed text-primary' : 'neu-flat text-slate-500'}`}
                >
                  {lang === 'en' ? 'EN' : lang === 'zh' ? '中文' : '日本語'}
                </button>
              ))}
            </div>
          </div>

          {/* Theme Mode Section */}
          <div>
            <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
              <SunIcon size={16} /> {t.theme}
            </label>
            <div className="flex gap-2">
               <button
                 onClick={() => setAppSettings(s => ({ ...s, theme: 'light' }))}
                 className={`flex-1 py-2 rounded-lg text-xs font-bold flex flex-col items-center gap-1 ${appSettings.theme === 'light' ? 'neu-pressed text-primary' : 'neu-flat text-slate-500'}`}
               >
                 <SunIcon size={16}/> {t.themeLight}
               </button>
               <button
                 onClick={() => setAppSettings(s => ({ ...s, theme: 'dark' }))}
                 className={`flex-1 py-2 rounded-lg text-xs font-bold flex flex-col items-center gap-1 ${appSettings.theme === 'dark' ? 'neu-pressed text-primary' : 'neu-flat text-slate-500'}`}
               >
                 <MoonIcon size={16}/> {t.themeDark}
               </button>
               <button
                 onClick={() => setAppSettings(s => ({ ...s, theme: 'system' }))}
                 className={`flex-1 py-2 rounded-lg text-xs font-bold flex flex-col items-center gap-1 ${appSettings.theme === 'system' ? 'neu-pressed text-primary' : 'neu-flat text-slate-500'}`}
               >
                 <MonitorIcon size={16}/> {t.themeSystem}
               </button>
            </div>
          </div>

          {/* Theme Color Picker */}
          <div>
             <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
                <SparklesIcon size={16} /> {t.themeColor}
             </label>
             <div className="flex justify-between px-2">
                {(['blue', 'purple', 'green', 'orange', 'pink'] as const).map(color => (
                  <button
                    key={color}
                    onClick={() => setAppSettings(s => ({ ...s, themeColor: color }))}
                    className={`w-8 h-8 rounded-full flex items-center justify-center transition-all ${appSettings.themeColor === color ? 'ring-2 ring-offset-2 ring-slate-400 scale-110' : ''}`}
                    style={{ backgroundColor: color === 'blue' ? '#3b82f6' : color === 'purple' ? '#8b5cf6' : color === 'green' ? '#10b981' : color === 'orange' ? '#f97316' : '#ec4899' }}
                  />
                ))}
             </div>
          </div>
          
          {/* Default Mode Section */}
          <div>
             <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
               <SettingsIcon size={16} /> {t.defaultMode}
             </label>
             <div className="flex bg-slate-200 dark:bg-slate-700/30 p-1 rounded-lg">
                <button 
                   onClick={() => setAppSettings(s => ({ ...s, defaultInputMode: 'single' }))}
                   className={`flex-1 py-1.5 text-xs font-bold rounded-md transition-all ${appSettings.defaultInputMode === 'single' ? 'bg-white dark:bg-slate-600 shadow-sm text-slate-800 dark:text-white' : 'text-slate-500'}`}
                >
                  {t.modeManual}
                </button>
                <button 
                   onClick={() => setAppSettings(s => ({ ...s, defaultInputMode: 'brainDump' }))}
                   className={`flex-1 py-1.5 text-xs font-bold rounded-md transition-all ${appSettings.defaultInputMode === 'brainDump' ? 'bg-white dark:bg-slate-600 shadow-sm text-slate-800 dark:text-white' : 'text-slate-500'}`}
                >
                  {t.modeAI}
                </button>
             </div>
          </div>

          <hr className="border-slate-300 dark:border-slate-700" />

          {/* AI Provider Config */}
          <div>
            <label className="block text-sm font-bold text-slate-500 mb-2">{t.provider}</label>
            <div className="flex gap-2 mb-3">
              <button
                onClick={() => setAiConfig(c => ({ ...c, provider: AIProvider.Gemini }))}
                className={`flex-1 py-2 rounded-lg text-sm font-bold ${aiConfig.provider === AIProvider.Gemini ? 'neu-pressed text-primary' : 'neu-flat text-slate-500'}`}
              >
                Gemini
              </button>
              <button
                onClick={() => setAiConfig(c => ({ ...c, provider: AIProvider.Custom }))}
                className={`flex-1 py-2 rounded-lg text-sm font-bold ${aiConfig.provider === AIProvider.Custom ? 'neu-pressed text-green-500' : 'neu-flat text-slate-500'}`}
              >
                Custom API
              </button>
            </div>

            {aiConfig.provider === AIProvider.Custom && (
              <div className="space-y-3 p-3 neu-concave rounded-xl">
                <div>
                  <label className="text-xs font-bold text-slate-400">{t.customBaseUrl}</label>
                  <input 
                    type="text" 
                    value={aiConfig.customBaseUrl}
                    onChange={(e) => setAiConfig(c => ({ ...c, customBaseUrl: e.target.value }))}
                    className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-1 text-sm outline-none text-slate-700 dark:text-slate-200"
                  />
                </div>
                <div>
                  <label className="text-xs font-bold text-slate-400">{t.customApiKey}</label>
                  <input 
                    type="password" 
                    value={aiConfig.customApiKey}
                    onChange={(e) => setAiConfig(c => ({ ...c, customApiKey: e.target.value }))}
                    className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-1 text-sm outline-none text-slate-700 dark:text-slate-200"
                  />
                </div>
                <div>
                  <label className="text-xs font-bold text-slate-400">{t.customModel}</label>
                  <input 
                    type="text" 
                    value={aiConfig.customModel}
                    onChange={(e) => setAiConfig(c => ({ ...c, customModel: e.target.value }))}
                    className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-1 text-sm outline-none text-slate-700 dark:text-slate-200"
                  />
                </div>
              </div>
            )}
          </div>
        </div>
      </Modal>

      {/* Decompose Alert Modal */}
      <Modal isOpen={!!decomposeTaskItem} onClose={() => setDecomposeTaskItem(null)} title={t.longTermDetected}>
        <div className="text-center space-y-4">
          <div className="mx-auto w-12 h-12 rounded-full bg-yellow-100 text-yellow-500 flex items-center justify-center">
            <AlertTriangleIcon />
          </div>
          <p className="text-slate-600 dark:text-slate-300 text-sm">
            "<span className="font-bold text-slate-800 dark:text-white">{decomposeTaskItem?.title}</span>" {t.longTermPrompt}
          </p>
          
          <div className="grid grid-cols-2 gap-3 mt-6">
            <button 
              onClick={() => setDecomposeTaskItem(null)}
              className="neu-flat py-2 rounded-lg text-slate-500 hover:text-slate-700 font-bold text-sm"
            >
              {t.keep}
            </button>
            <button 
              onClick={handleDecomposeConfirm}
              disabled={isDecomposing}
              className="neu-btn py-2 rounded-lg text-yellow-600 dark:text-yellow-500 font-bold text-sm flex items-center justify-center gap-2"
            >
              {isDecomposing ? <LoaderIcon className="animate-spin" size={16}/> : t.decompose}
            </button>
          </div>
        </div>
      </Modal>

    </div>
  );
}
