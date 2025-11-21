
import React, { useState, useEffect, useRef } from 'react';
import { Task, QuadrantType, AIConfig, AIProvider, AIAnalysisResult, AppSettings, InputMode, Board, ThemeColor, SubTask } from './types';
import { analyzeTasks, decomposeTasksBatch } from './services/aiService';
import { translations } from './translations';
import { 
  SparklesIcon, SettingsIcon, PlusIcon, XIcon, 
  AlertTriangleIcon, LoaderIcon, SplitIcon, TrashIcon,
  MoonIcon, SunIcon, GlobeIcon, MonitorIcon, CalendarIcon, LayersIcon
} from './components/Icons';

// --- Interfaces ---

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: string;
  hideClose?: boolean;
}

interface TaskCardProps {
  task: Task;
  onDragStart: (e: React.DragEvent, task: Task) => void;
  onDelete: (id: string) => void;
  onDecompose: (task: Task) => void;
  onUpdate: (task: Task) => void;
  colors: { border: string, text: string };
  t: any;
  isSelectionMode: boolean;
  isSelected: boolean;
  onToggleSelect: (id: string) => void;
  onEdit: (task: Task, subTaskId?: string) => void;
}

interface QuadrantProps {
  type: QuadrantType;
  title: string;
  shortTitle: string;
  colorCode: string;
  tasks: Task[];
  onDrop: (e: React.DragEvent, quadrant: QuadrantType) => void;
  onDragOver: (e: React.DragEvent) => void;
  onDragStart: (e: React.DragEvent, task: Task) => void;
  onDelete: (id: string) => void;
  onDecompose: (task: Task) => void;
  onUpdate: (task: Task) => void;
  t: any;
  isSelectionMode: boolean;
  selectedTaskIds: Set<string>;
  onToggleSelect: (id: string) => void;
  onEdit: (task: Task, subTaskId?: string) => void;
}

// --- Components ---

const Modal: React.FC<ModalProps> = ({ isOpen, onClose, children, title, hideClose = false }) => {
  if (!isOpen) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm animate-fade-in">
      <div className="neu-flat dark:text-slate-200 rounded-2xl w-full max-w-md p-6 relative animate-slide-up overflow-hidden max-h-[90vh] flex flex-col">
        <div className="flex justify-between items-center mb-4 flex-none">
          {title && <h2 className="text-xl font-bold">{title}</h2>}
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

const TaskCard: React.FC<TaskCardProps> = ({ 
  task, 
  onDragStart, 
  onDelete, 
  onDecompose,
  onUpdate,
  colors,
  t,
  isSelectionMode,
  isSelected,
  onToggleSelect,
  onEdit
}) => {
  
  const [newSubtask, setNewSubtask] = useState('');
  const [isAddingSub, setIsAddingSub] = useState(false);

  const calculateDaysLeft = (timestamp?: number) => {
    if (!timestamp) return null;
    return Math.ceil((timestamp - Date.now()) / (1000 * 60 * 60 * 24));
  };

  const daysLeft = calculateDaysLeft(task.deadline);
  
  const getDeadlineColor = (days: number) => {
    if (days < 0) return 'text-red-500 font-bold';
    if (days <= 2) return 'text-orange-500 font-bold';
    return 'text-slate-400';
  };

  const handleAddSubtask = () => {
    if (!newSubtask.trim()) return;
    const sub: SubTask = { id: crypto.randomUUID(), title: newSubtask, completed: false };
    onUpdate({ ...task, subtasks: [...(task.subtasks || []), sub] });
    setNewSubtask('');
    setIsAddingSub(false);
  };

  const toggleSubtask = (subId: string) => {
    if (!task.subtasks) return;
    const updatedSubs = task.subtasks.map(s => s.id === subId ? { ...s, completed: !s.completed } : s);
    onUpdate({ ...task, subtasks: updatedSubs });
  };

  const deleteSubtask = (subId: string) => {
    if (!task.subtasks) return;
    const updatedSubs = task.subtasks.filter(s => s.id !== subId);
    onUpdate({ ...task, subtasks: updatedSubs });
  };

  return (
    <div
      draggable={!isSelectionMode}
      onDragStart={(e) => onDragStart(e, task)}
      onClick={() => isSelectionMode && onToggleSelect(task.id)}
      onDoubleClick={(e) => { e.stopPropagation(); onEdit(task); }}
      className={`neu-btn p-3 mb-3 rounded-xl cursor-grab active:cursor-grabbing group relative overflow-hidden flex flex-col gap-2
        ${isSelected ? 'ring-2 ring-primary bg-primary/5' : ''}
      `}
    >
      {task.isLongTerm && !task.subtasks?.length && (
        <div className="absolute top-0 left-0 w-1 h-full bg-yellow-400/50" />
      )}
      
      <div className="flex justify-between items-start gap-2 w-full">
        {isSelectionMode && (
          <div className={`w-5 h-5 rounded border flex-none flex items-center justify-center ${isSelected ? 'bg-primary border-primary text-white' : 'border-slate-400'}`}>
             {isSelected && <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" /></svg>}
          </div>
        )}
        
        <div className="flex-1 min-w-0">
           <p className="text-sm font-bold text-slate-700 dark:text-slate-200 break-words leading-tight">
            {task.title}
           </p>
        </div>

        {/* Meta Section: Deadline + Actions */}
        <div className="flex items-center gap-2 flex-none">
            {/* Right-aligned deadline */}
            {daysLeft !== null && (
             <div className={`text-xs flex items-center gap-1 ${getDeadlineColor(daysLeft)} whitespace-nowrap`}>
               {daysLeft < 0 ? t.overdue : daysLeft === 0 ? t.today : `${daysLeft}${t.daysLeft}`}
               <CalendarIcon size={10} />
             </div>
           )}

            {!isSelectionMode && (
              <div className="flex items-center gap-1 opacity-60 hover:opacity-100 transition-opacity ml-1">
                {task.isLongTerm && !task.subtasks?.length && (
                  <button 
                    onClick={(e) => { e.stopPropagation(); onDecompose(task); }}
                    className="text-yellow-500 hover:scale-110 transition-transform p-1"
                    title="Decompose"
                  >
                    <SplitIcon size={14} />
                  </button>
                )}
                <button 
                  onClick={(e) => { e.stopPropagation(); setIsAddingSub(!isAddingSub); }}
                  className="text-slate-400 hover:text-primary transition-colors p-1"
                  title={t.addSubtask}
                >
                  <PlusIcon size={14} />
                </button>
                <button 
                  onClick={(e) => { e.stopPropagation(); onDelete(task.id); }}
                  className="text-red-400 hover:scale-110 transition-transform p-1"
                  title="Delete"
                >
                  <TrashIcon size={14} />
                </button>
              </div>
            )}
        </div>
      </div>

      {/* Subtasks List */}
      {task.subtasks && task.subtasks.length > 0 && (
        <div className="mt-1 pl-2 border-l-2 border-slate-200 dark:border-slate-700 space-y-1">
          {task.subtasks.map(sub => {
             const subDays = calculateDaysLeft(sub.deadline);
             return (
                <div 
                  key={sub.id} 
                  className="flex items-center gap-2 text-xs group/sub"
                  onDoubleClick={(e) => { e.stopPropagation(); onEdit(task, sub.id); }}
                >
                  <button 
                    onClick={(e) => { e.stopPropagation(); toggleSubtask(sub.id); }}
                    className={`w-3 h-3 rounded-sm border flex-none ${sub.completed ? 'bg-slate-400 border-slate-400' : 'border-slate-400'}`}
                  />
                  <span className={`flex-1 ${sub.completed ? 'line-through text-slate-400' : 'text-slate-600 dark:text-slate-300'}`}>
                    {sub.title}
                  </span>
                  
                  {subDays !== null && !sub.completed && (
                     <span className={`text-[10px] ${getDeadlineColor(subDays)}`}>
                        {subDays}d
                     </span>
                  )}

                  <button 
                     onClick={(e) => { e.stopPropagation(); deleteSubtask(sub.id); }}
                     className="opacity-0 group-hover/sub:opacity-100 text-red-400 p-0.5"
                  >
                    <XIcon size={10} />
                  </button>
                </div>
             );
          })}
        </div>
      )}

      {/* Add Subtask Input */}
      {isAddingSub && (
        <div className="mt-2 flex gap-1 items-center">
          <input 
            autoFocus
            value={newSubtask}
            onChange={(e) => setNewSubtask(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleAddSubtask()}
            placeholder={t.addSubtask}
            className="flex-1 bg-white dark:bg-slate-700 text-xs p-1 rounded border border-slate-200 dark:border-slate-600 outline-none"
          />
          <button onClick={handleAddSubtask} className="text-primary"><PlusIcon size={14}/></button>
        </div>
      )}
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
  onUpdate,
  t,
  isSelectionMode,
  selectedTaskIds,
  onToggleSelect,
  onEdit
}) => {
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
              onUpdate={onUpdate}
              colors={styles}
              t={t}
              isSelectionMode={isSelectionMode}
              isSelected={selectedTaskIds.has(task.id)}
              onToggleSelect={onToggleSelect}
              onEdit={onEdit}
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
  
  // New Workflow State: Group Suggestion Queue & Batch Long-Term Queue
  const [pendingTasks, setPendingTasks] = useState<Task[]>([]);
  const [groupingQueue, setGroupingQueue] = useState<Task[]>([]);
  const [longTermBatchQueue, setLongTermBatchQueue] = useState<Task[]>([]);
  const [longTermSelectedIds, setLongTermSelectedIds] = useState<Set<string>>(new Set());
  
  // Single Decompose State
  const [singleDecomposingTask, setSingleDecomposingTask] = useState<Task | null>(null);

  // Grouping State
  const [isSelectionMode, setIsSelectionMode] = useState(false);
  const [selectedTaskIds, setSelectedTaskIds] = useState<Set<string>>(new Set());
  const [groupModalOpen, setGroupModalOpen] = useState(false);
  const [groupTitleInput, setGroupTitleInput] = useState('');

  // Edit State
  const [editingTask, setEditingTask] = useState<{ task: Task, subId?: string } | null>(null);
  const [editDateInput, setEditDateInput] = useState('');

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
    defaultInputMode: 'single',
    autoGroupAI: false,
    urgencyThresholdDays: 3
  });

  // Helper for translations
  const t = translations[appSettings.language];

  // --- Effects ---

  useEffect(() => {
    const savedConfig = localStorage.getItem('matrixflow-config');
    if (savedConfig) setAiConfig(JSON.parse(savedConfig));

    const savedSettings = localStorage.getItem('matrixflow-settings');
    if (savedSettings) {
      const parsed = JSON.parse(savedSettings);
      setAppSettings({
         ...parsed,
         autoGroupAI: parsed.autoGroupAI ?? false,
         urgencyThresholdDays: parsed.urgencyThresholdDays ?? 3
      });
      setInputMode(parsed.defaultInputMode); 
    }

    const savedBoards = localStorage.getItem('matrixflow-boards');
    const savedTasks = localStorage.getItem('matrixflow-tasks');
    
    let loadedBoards: Board[] = [];
    let loadedTasks: Task[] = [];

    if (savedBoards) {
      loadedBoards = JSON.parse(savedBoards);
    }
    
    if (savedTasks) {
      const rawTasks = JSON.parse(savedTasks);
      if (rawTasks.length > 0 && !rawTasks[0].boardId) {
        const defaultBoardId = crypto.randomUUID();
        if (loadedBoards.length === 0) {
          loadedBoards.push({ id: defaultBoardId, name: t.defaultBoardName, createdAt: Date.now() });
        }
        const targetBoardId = loadedBoards[0]?.id || defaultBoardId;
        loadedTasks = rawTasks.map((task: any) => ({ ...task, boardId: targetBoardId }));
      } else {
        loadedTasks = rawTasks;
      }
    }

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

  // Auto-Move Tasks based on Deadline
  useEffect(() => {
     if (tasks.length === 0) return;
     
     const checkDeadlines = () => {
       const now = Date.now();
       const thresholdMs = appSettings.urgencyThresholdDays * 24 * 60 * 60 * 1000;
       
       let hasChanges = false;
       const updatedTasks = tasks.map(task => {
         if (!task.deadline || task.completed) return task;

         const timeLeft = task.deadline - now;
         // Move Q2 (Plan) -> Q1 (Do)
         if (task.quadrant === QuadrantType.Plan && timeLeft <= thresholdMs) {
           hasChanges = true;
           return { ...task, quadrant: QuadrantType.Do };
         }
         // Move Q4 (Eliminate) -> Q3 (Delegate)
         if (task.quadrant === QuadrantType.Eliminate && timeLeft <= thresholdMs) {
           hasChanges = true;
           return { ...task, quadrant: QuadrantType.Delegate };
         }
         return task;
       });

       if (hasChanges) {
         setTasks(updatedTasks);
       }
     };

     checkDeadlines();
     const interval = setInterval(checkDeadlines, 1000 * 60 * 60);
     return () => clearInterval(interval);

  }, [tasks, appSettings.urgencyThresholdDays]);

  // Theme & Color Handling
  useEffect(() => {
    const root = window.document.documentElement;
    root.classList.remove('light', 'dark');
    if (appSettings.theme === 'system') {
      if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
        root.classList.add('dark');
      } else {
        root.classList.add('light');
      }
    } else {
      root.classList.add(appSettings.theme);
    }
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
      const results = await analyzeTasks(
        rawTasks, 
        aiConfig, 
        appSettings.language, 
        appSettings.autoGroupAI
      );
      
      const newTasks: Task[] = results.map(res => ({
        id: crypto.randomUUID(),
        boardId: activeBoardId,
        title: res.title,
        quadrant: res.quadrant,
        isLongTerm: res.isLongTerm,
        completed: false,
        createdAt: Date.now(),
        subtasks: res.subtasks?.map(st => ({
          id: crypto.randomUUID(),
          title: st,
          completed: false
        })) || []
      }));
      
      // PHASE 1 Complete. 
      setInputText('');
      if (addModalOpen) setAddModalOpen(false);

      // Start Workflow:
      // If AutoGroup is OFF, we need to verify groups first.
      // We put all new tasks into pendingTasks initially, but we actually iterate queues.
      
      if (!appSettings.autoGroupAI) {
        // Find tasks that have subtasks (suggested groups)
        const potentialGroups = newTasks.filter(t => t.subtasks && t.subtasks.length > 0);
        const others = newTasks.filter(t => !t.subtasks || t.subtasks.length === 0);
        
        // "others" are ready for the next phase (long term check)
        setPendingTasks(others);
        
        if (potentialGroups.length > 0) {
          setGroupingQueue(potentialGroups);
          // processing stays true until queues are empty
          return; 
        } else {
           // No groups to check, proceed directly to long term check
           initiateLongTermCheck(others);
           return;
        }
      } else {
         // Auto Group is ON, accept all structure as is
         initiateLongTermCheck(newTasks);
         return;
      }
      
    } catch (err) {
      alert(`${t.error}: ` + (err instanceof Error ? err.message : String(err)));
      setIsProcessing(false);
    } 
  };

  const initiateLongTermCheck = (tasksToCheck: Task[]) => {
      const longTerms = tasksToCheck.filter(t => t.isLongTerm);
      
      // Add non-long-terms directly to board
      setTasks(prev => [...tasksToCheck, ...prev]); 
      
      if (longTerms.length > 0) {
          const trueLongTerms = longTerms.filter(t => !t.subtasks || t.subtasks.length === 0);
          
          if (trueLongTerms.length > 0) {
              setLongTermBatchQueue(trueLongTerms);
              const initialIds = new Set<string>();
              trueLongTerms.forEach(t => initialIds.add(t.id));
              setLongTermSelectedIds(initialIds); // Default all to checked
              
              // Important: Turn off loading spinner so user can interact with the modal
              setIsProcessing(false);
          } else {
              setIsProcessing(false);
          }
      } else {
          setIsProcessing(false);
      }
  };

  // Workflow: Handle Group Suggestion
  const handleGroupDecision = (accepted: boolean) => {
      const currentGroup = groupingQueue[0];
      const remainingQueue = groupingQueue.slice(1);
      
      let finalTasks: Task[] = [];
      
      if (accepted) {
          // Keep as group
          finalTasks = [currentGroup];
      } else {
          // Split into individual tasks
          if (currentGroup.subtasks) {
              finalTasks = currentGroup.subtasks.map(sub => ({
                  id: crypto.randomUUID(),
                  boardId: currentGroup.boardId,
                  title: sub.title,
                  quadrant: currentGroup.quadrant,
                  isLongTerm: false, // Assuming split items are simple
                  completed: false,
                  createdAt: Date.now(),
                  subtasks: []
              }));
          } else {
              // Fallback (shouldn't happen)
              finalTasks = [currentGroup];
          }
      }
      
      // Add decided tasks to pending pool for next phase
      const updatedPending = [...pendingTasks, ...finalTasks];
      setPendingTasks(updatedPending);
      setGroupingQueue(remainingQueue);

      if (remainingQueue.length === 0) {
          // All groups resolved, move to next phase
          initiateLongTermCheck(updatedPending);
      }
  };

  // Workflow: Handle Batch Decomposition
  const handleBatchDecompose = async () => {
      if (longTermSelectedIds.size === 0) {
          setLongTermBatchQueue([]);
          setIsProcessing(false);
          return;
      }

      setIsProcessing(true); // Show spinner on button
      try {
          const tasksToDecompose = longTermBatchQueue.filter(t => longTermSelectedIds.has(t.id));
          const titles = tasksToDecompose.map(t => t.title);
          
          const results = await decomposeTasksBatch(titles, aiConfig, appSettings.language);
          
          // Update tasks in state
          setTasks(prev => prev.map(t => {
              if (!longTermSelectedIds.has(t.id)) return t;
              
              const result = results.find(r => r.originalTitle === t.title); // Matching by title
              if (result) {
                  const newSubs: SubTask[] = result.subtasks.map(st => ({
                      id: crypto.randomUUID(),
                      title: st,
                      completed: false
                  }));
                  return { ...t, subtasks: [...(t.subtasks || []), ...newSubs] };
              }
              return t;
          }));

      } catch (err) {
          console.error(err);
          alert(t.error);
      } finally {
          setLongTermBatchQueue([]);
          setIsProcessing(false);
          setLongTermSelectedIds(new Set());
      }
  };

  const handleSkipBatchDecompose = () => {
    setLongTermBatchQueue([]);
    setIsProcessing(false);
    setLongTermSelectedIds(new Set());
  };

  // Individual Decompose (Legacy/Manual trigger) - IMMEDIATE action
  const handleManualDecompose = async (task: Task) => {
      setSingleDecomposingTask(task);
      
      try {
          const results = await decomposeTasksBatch([task.title], aiConfig, appSettings.language);
          const result = results[0];
          
          if (result) {
             const newSubs: SubTask[] = result.subtasks.map(st => ({
                 id: crypto.randomUUID(),
                 title: st,
                 completed: false
             }));
             
             setTasks(prev => prev.map(t => 
                 t.id === task.id ? { ...t, subtasks: [...(t.subtasks || []), ...newSubs] } : t
             ));
          }
      } catch (err) {
         console.error(err);
         alert(t.error);
      } finally {
         setSingleDecomposingTask(null);
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
      createdAt: Date.now(),
    };
    setTasks(prev => [newTask, ...prev]);
    setInputText('');
    if (addModalOpen) setAddModalOpen(false);
  };

  const handleTaskUpdate = (updatedTask: Task) => {
    setTasks(prev => prev.map(t => t.id === updatedTask.id ? updatedTask : t));
  };

  // Selection & Grouping Handlers
  const toggleSelectionMode = () => {
    setIsSelectionMode(!isSelectionMode);
    setSelectedTaskIds(new Set());
  };

  const handleToggleSelect = (id: string) => {
    const newSet = new Set(selectedTaskIds);
    if (newSet.has(id)) newSet.delete(id);
    else newSet.add(id);
    setSelectedTaskIds(newSet);
  };

  const openGroupModal = () => {
      if (selectedTaskIds.size < 2) return;
      setGroupTitleInput('');
      setGroupModalOpen(true);
  };

  const handleConfirmGroup = () => {
    if (!groupTitleInput.trim()) {
        setGroupModalOpen(false); // Cancel if empty
        return;
    }

    const selectedTasks = tasks.filter(t => selectedTaskIds.has(t.id));
    if (selectedTasks.length === 0) return;

    const firstTask = selectedTasks[0];
    
    // Convert selected tasks into subtasks
    const newSubtasks: SubTask[] = selectedTasks.map(t => ({
      id: crypto.randomUUID(),
      title: t.title,
      completed: t.completed,
      deadline: t.deadline // Preserve deadline if exists
    }));

    // Create Parent Task
    const parentTask: Task = {
      id: crypto.randomUUID(),
      boardId: firstTask.boardId,
      title: groupTitleInput,
      quadrant: firstTask.quadrant,
      isLongTerm: false,
      completed: false,
      createdAt: Date.now(),
      subtasks: newSubtasks,
      deadline: undefined
    };

    setTasks(prev => {
      // Remove original selected tasks
      const remaining = prev.filter(t => !selectedTaskIds.has(t.id));
      return [parentTask, ...remaining];
    });

    setGroupModalOpen(false);
    setIsSelectionMode(false);
    setSelectedTaskIds(new Set());
  };

  // Edit Handlers
  const openEditModal = (task: Task, subId?: string) => {
      setEditingTask({ task, subId });
      
      let currentDeadline: number | undefined;
      if (subId && task.subtasks) {
          const sub = task.subtasks.find(s => s.id === subId);
          currentDeadline = sub?.deadline;
      } else {
          currentDeadline = task.deadline;
      }

      if (currentDeadline) {
          setEditDateInput(new Date(currentDeadline).toISOString().split('T')[0]);
      } else {
          setEditDateInput('');
      }
  };

  const saveEdit = () => {
      if (!editingTask) return;
      
      const timestamp = editDateInput ? new Date(editDateInput).getTime() : undefined;
      
      if (editingTask.subId) {
          // Update subtask
           const updatedSubs = (editingTask.task.subtasks || []).map(s => 
              s.id === editingTask.subId ? { ...s, deadline: timestamp } : s
           );
           handleTaskUpdate({ ...editingTask.task, subtasks: updatedSubs });
      } else {
          // Update parent task
          handleTaskUpdate({ ...editingTask.task, deadline: timestamp });
      }
      setEditingTask(null);
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
    if (boards.length <= 1) return; 
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
           {/* Logo Removed as requested */}
          
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
        
        <div className="flex items-center gap-2">
            {/* Selection Mode Toggle */}
            <button 
              onClick={toggleSelectionMode}
              className={`neu-btn px-3 py-2 rounded-lg transition-colors flex items-center gap-2 ${isSelectionMode ? 'text-primary ring-1 ring-primary' : 'text-slate-500 dark:text-slate-400'}`}
            >
              <LayersIcon size={18} />
              <span className="hidden md:inline text-xs font-bold">{isSelectionMode ? t.cancelSelection : t.selectionMode}</span>
            </button>
            
            {isSelectionMode && selectedTaskIds.size >= 2 && (
               <button 
                 onClick={openGroupModal}
                 className="neu-btn px-3 py-2 rounded-lg text-primary font-bold text-xs animate-fade-in"
               >
                 {t.groupSelected} ({selectedTaskIds.size})
               </button>
            )}

            <button 
              onClick={() => setSettingsOpen(true)}
              className="neu-btn p-3 rounded-full text-slate-500 dark:text-slate-400 hover:text-primary transition-colors"
            >
              <SettingsIcon />
            </button>
        </div>
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
            onDecompose={handleManualDecompose}
            onUpdate={handleTaskUpdate}
            t={t}
            isSelectionMode={isSelectionMode}
            selectedTaskIds={selectedTaskIds}
            onToggleSelect={handleToggleSelect}
            onEdit={openEditModal}
          />
          <Quadrant 
            type={QuadrantType.Plan} 
            title={t.q2} shortTitle={t.q2Short} colorCode="q2"
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Plan)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDelete={id => setTasks(prev => prev.filter(t => t.id !== id))}
            onDecompose={handleManualDecompose}
            onUpdate={handleTaskUpdate}
            t={t}
            isSelectionMode={isSelectionMode}
            selectedTaskIds={selectedTaskIds}
            onToggleSelect={handleToggleSelect}
            onEdit={openEditModal}
          />
          <Quadrant 
            type={QuadrantType.Delegate} 
            title={t.q3} shortTitle={t.q3Short} colorCode="q3"
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Delegate)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDelete={id => setTasks(prev => prev.filter(t => t.id !== id))}
            onDecompose={handleManualDecompose}
            onUpdate={handleTaskUpdate}
            t={t}
            isSelectionMode={isSelectionMode}
            selectedTaskIds={selectedTaskIds}
            onToggleSelect={handleToggleSelect}
            onEdit={openEditModal}
          />
          <Quadrant 
            type={QuadrantType.Eliminate} 
            title={t.q4} shortTitle={t.q4Short} colorCode="q4"
            tasks={activeTasks.filter(t => t.quadrant === QuadrantType.Eliminate)}
            onDrop={handleDrop} onDragOver={handleDragOver} onDragStart={handleDragStart}
            onDelete={id => setTasks(prev => prev.filter(t => t.id !== id))}
            onDecompose={handleManualDecompose}
            onUpdate={handleTaskUpdate}
            t={t}
            isSelectionMode={isSelectionMode}
            selectedTaskIds={selectedTaskIds}
            onToggleSelect={handleToggleSelect}
            onEdit={openEditModal}
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
        <div className="space-y-6">
          
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

          {/* Grouping & Automation */}
          <div>
             <label className="block text-sm font-bold text-slate-500 mb-2 flex items-center gap-2">
               <LayersIcon size={16} /> {t.grouping}
             </label>
             
             <div className="neu-concave rounded-xl p-3 space-y-4">
                {/* Auto Group Toggle */}
                <div className="flex items-center justify-between">
                   <div>
                     <p className="text-sm font-bold text-slate-700 dark:text-slate-200">{t.autoGroupAI}</p>
                     <p className="text-xs text-slate-500">{t.autoGroupDesc}</p>
                   </div>
                   <button 
                     onClick={() => setAppSettings(s => ({ ...s, autoGroupAI: !s.autoGroupAI }))}
                     className={`w-10 h-5 rounded-full relative transition-colors ${appSettings.autoGroupAI ? 'bg-primary' : 'bg-slate-300 dark:bg-slate-600'}`}
                   >
                     <div className={`absolute top-1 w-3 h-3 rounded-full bg-white transition-transform ${appSettings.autoGroupAI ? 'left-6' : 'left-1'}`}></div>
                   </button>
                </div>

                <div className="h-px bg-slate-200 dark:bg-slate-700"></div>

                {/* Urgency Threshold */}
                <div>
                   <div className="flex justify-between mb-1">
                     <p className="text-sm font-bold text-slate-700 dark:text-slate-200">{t.urgencyThreshold}</p>
                     <span className="text-xs font-bold text-primary bg-primary/10 px-2 rounded">{appSettings.urgencyThresholdDays} {t.daysLeft.split(' ')[0]}</span>
                   </div>
                   <p className="text-xs text-slate-500 mb-2">{t.urgencyDesc}</p>
                   <input 
                     type="range" 
                     min="1" max="14" 
                     value={appSettings.urgencyThresholdDays} 
                     onChange={(e) => setAppSettings(s => ({ ...s, urgencyThresholdDays: parseInt(e.target.value) }))}
                     className="w-full accent-primary h-1 bg-slate-300 rounded-lg appearance-none cursor-pointer"
                   />
                </div>
             </div>
          </div>
          
          <hr className="border-slate-300 dark:border-slate-700" />

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

      {/* Suggest Group Modal (Step 1 of workflow) */}
      <Modal isOpen={groupingQueue.length > 0} onClose={() => handleGroupDecision(false)} title={t.suggestedGroup}>
         {groupingQueue.length > 0 && (
            <div className="space-y-4">
               <p className="text-sm text-slate-500 dark:text-slate-400">{t.suggestedGroupPrompt}</p>
               <div className="neu-concave p-3 rounded-xl">
                  <p className="font-bold text-lg text-center mb-2 text-primary">{groupingQueue[0].title}</p>
                  <p className="text-xs text-slate-400 font-bold mb-1 uppercase tracking-wider">{t.groupContents}</p>
                  <ul className="text-sm text-slate-600 dark:text-slate-300 space-y-1">
                      {groupingQueue[0].subtasks?.map((s, i) => (
                          <li key={i} className="flex items-center gap-2">
                              <span className="w-1 h-1 rounded-full bg-slate-400"></span>
                              {s.title}
                          </li>
                      ))}
                  </ul>
               </div>
               
               <div className="flex gap-3 pt-2">
                   <button 
                     onClick={() => handleGroupDecision(false)}
                     className="flex-1 py-2 rounded-lg border border-slate-300 dark:border-slate-600 text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors font-bold text-sm"
                   >
                     {t.skipGroup}
                   </button>
                   <button 
                     onClick={() => handleGroupDecision(true)}
                     className="flex-1 py-2 rounded-lg bg-primary text-white font-bold text-sm hover:opacity-90 shadow-lg shadow-primary/30"
                   >
                     {t.confirmGroupBtn}
                   </button>
               </div>
            </div>
         )}
      </Modal>

      {/* Batch Decompose Modal (Step 2 of workflow) */}
      <Modal isOpen={longTermBatchQueue.length > 0} onClose={() => { setLongTermBatchQueue([]); setIsProcessing(false); }} title={t.batchReviewTitle}>
         <div className="space-y-4">
            <p className="text-sm text-slate-500 dark:text-slate-400">{t.batchReviewDesc}</p>
            
            <div className="space-y-2 max-h-[50vh] overflow-y-auto custom-scrollbar p-1">
                {longTermBatchQueue.map(task => (
                    <div key={task.id} className="neu-flat p-3 rounded-xl flex items-center gap-3">
                        <input 
                          type="checkbox" 
                          checked={longTermSelectedIds.has(task.id)}
                          onChange={() => {
                              const newSet = new Set(longTermSelectedIds);
                              if (newSet.has(task.id)) newSet.delete(task.id);
                              else newSet.add(task.id);
                              setLongTermSelectedIds(newSet);
                          }}
                          className="w-5 h-5 accent-primary cursor-pointer"
                        />
                        <div className="flex-1">
                            <p className="font-bold text-slate-700 dark:text-slate-200">{task.title}</p>
                            <p className="text-xs text-slate-400">
                                {task.quadrant === 1 ? t.q1 : task.quadrant === 2 ? t.q2 : task.quadrant === 3 ? t.q3 : t.q4}
                            </p>
                        </div>
                        <div className="text-yellow-500">
                            <SplitIcon size={18} />
                        </div>
                    </div>
                ))}
            </div>

            <div className="flex gap-3 pt-2">
                <button 
                   onClick={handleSkipBatchDecompose}
                   disabled={isProcessing}
                   className="flex-1 py-3 rounded-xl border border-slate-300 dark:border-slate-600 text-slate-500 font-bold text-sm hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
                >
                   {t.skipBatch}
                </button>
                <button 
                   onClick={handleBatchDecompose}
                   disabled={isProcessing}
                   className="flex-[2] neu-btn py-3 rounded-xl font-bold text-primary flex justify-center items-center gap-2 hover:opacity-90"
                >
                   {isProcessing ? (
                       <>
                         <LoaderIcon className="animate-spin" />
                         {t.processingBatch}
                       </>
                   ) : (
                       <>
                         <SparklesIcon />
                         {t.processBatch} ({longTermSelectedIds.size})
                       </>
                   )}
                </button>
            </div>
         </div>
      </Modal>

      {/* Single Task Decompose Modal (Immediate Feedback) */}
      <Modal isOpen={!!singleDecomposingTask} onClose={() => {}} hideClose={true}>
          <div className="flex flex-col items-center justify-center py-8 space-y-4">
             <p className="text-xl font-bold text-slate-700 dark:text-slate-200">{singleDecomposingTask?.title}</p>
             <LoaderIcon className="animate-spin text-primary" size={48} />
             <p className="text-sm text-slate-500 dark:text-slate-400 font-bold animate-pulse">{t.decomposingSingle}</p>
          </div>
      </Modal>

      {/* Task/Subtask Edit Modal */}
      <Modal isOpen={!!editingTask} onClose={() => setEditingTask(null)} title={editingTask?.subId ? t.editSubtask : t.editTask}>
         <div className="space-y-4">
             <div>
                 <label className="block text-xs font-bold text-slate-500 mb-1">{t.setDeadline}</label>
                 <input 
                   type="date" 
                   value={editDateInput}
                   onChange={(e) => setEditDateInput(e.target.value)}
                   className="w-full bg-transparent border-b border-slate-300 dark:border-slate-600 py-2 text-lg outline-none text-slate-700 dark:text-slate-200 font-mono"
                 />
             </div>
             <div className="flex justify-end gap-2 mt-4">
                 <button 
                   onClick={saveEdit}
                   className="neu-btn px-4 py-2 rounded-lg text-primary font-bold text-sm"
                 >
                   {t.addSingleBtn}
                 </button>
             </div>
         </div>
      </Modal>

      {/* Manual Grouping Modal */}
      <Modal isOpen={groupModalOpen} onClose={() => setGroupModalOpen(false)} title={t.confirmGroup}>
         <div className="space-y-4">
            <p className="text-sm text-slate-500">{t.groupingPrompt}</p>
            <div className="flex flex-wrap gap-2 mb-2">
                {Array.from(selectedTaskIds).map(id => {
                    const task = tasks.find(t => t.id === id);
                    return task ? (
                        <span key={id} className="text-xs bg-slate-200 dark:bg-slate-700 px-2 py-1 rounded text-slate-600 dark:text-slate-300">
                            {task.title}
                        </span>
                    ) : null;
                })}
            </div>
            <input 
              autoFocus
              type="text"
              value={groupTitleInput}
              onChange={(e) => setGroupTitleInput(e.target.value)}
              placeholder={t.groupTitlePlaceholder}
              onKeyDown={(e) => e.key === 'Enter' && handleConfirmGroup()}
              className="w-full neu-pressed p-3 rounded-xl outline-none bg-transparent text-slate-700 dark:text-slate-200"
            />
            <div className="flex justify-end gap-2">
                 <button 
                   onClick={handleConfirmGroup}
                   className="neu-btn px-4 py-2 rounded-lg text-primary font-bold text-sm"
                 >
                   {t.confirmGroup}
                 </button>
            </div>
         </div>
      </Modal>

    </div>
  );
}
