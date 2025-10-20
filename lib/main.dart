import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TaskApp());
}

enum Priority { high, medium, low }

extension PriorityX on Priority {
  String get label => switch (this) {
        Priority.high => 'High',
        Priority.medium => 'Medium',
        Priority.low => 'Low',
      };

  int get rank => switch (this) {
        Priority.high => 0,
        Priority.medium => 1,
        Priority.low => 2,
      };

  static Priority fromString(String s) => switch (s) {
        'high' => Priority.high,
        'medium' => Priority.medium,
        _ => Priority.low,
      };

  String get asString => switch (this) {
        Priority.high => 'high',
        Priority.medium => 'medium',
        Priority.low => 'low',
      };
}

class Task {
  String name;
  bool completed;
  Priority priority;

  Task({
    required this.name,
    this.completed = false,
    this.priority = Priority.low,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'completed': completed,
        'priority': priority.asString,
      };

  static Task fromJson(Map<String, dynamic> map) => Task(
        name: map['name'] ?? '',
        completed: map['completed'] ?? false,
        priority: PriorityX.fromString(map['priority'] ?? 'low'),
      );
}

class TaskApp extends StatefulWidget {
  const TaskApp({super.key});
  @override
  State<TaskApp> createState() => _TaskAppState();
}

class _TaskAppState extends State<TaskApp> {
  bool _isDark = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDark = prefs.getBool('isDark') ?? true);
  }

  Future<void> _saveTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', value);
  }

  void _toggleTheme() {
    setState(() => _isDark = !_isDark);
    _saveTheme(_isDark);
  }

  ThemeData _buildDarkTheme() {
    const accent = Color(0xFFB36BFF);
    const deepBg = Color(0xFF0C0C11);
    const cardBg = Color(0xFF151520);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: deepBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        primary: accent,
        background: deepBg,
        surface: cardBg,
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4, // subtle glow simulation
        shadowColor: Colors.white.withOpacity(0.12),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    const accent = Color(0xFFB36BFF);
    const bg = Color(0xFFD0D0D3);
    const cardBg = Color(0xFFE4E4E7);
    const text = Color(0xFF1A1A1C);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        primary: accent,
        background: bg,
        surface: cardBg,
        onSurface: text,
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.08),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Manager',
      debugShowCheckedModeBanner: false,
      theme: _isDark ? _buildDarkTheme() : _buildLightTheme(),
      home: TaskListScreen(
        isDark: _isDark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class TaskListScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const TaskListScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final TextEditingController _taskCtrl = TextEditingController();
  final String _storageKey = 'tasks_v1';
  Priority _newTaskPriority = Priority.medium;
  List<Task> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final list = json.decode(raw) as List;
      _tasks = list.map((e) => Task.fromJson(e)).toList();
      _sortTasks();
    }
    setState(() {});
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      json.encode(_tasks.map((t) => t.toJson()).toList()),
    );
  }

  void _sortTasks() {
    _tasks.sort((a, b) {
      final byPriority = a.priority.rank.compareTo(b.priority.rank);
      if (byPriority != 0) return byPriority;
      final byComplete =
          (a.completed ? 1 : 0).compareTo(b.completed ? 1 : 0);
      if (byComplete != 0) return byComplete;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  void _addTask() {
    final text = _taskCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _tasks.add(Task(name: text, priority: _newTaskPriority));
      _taskCtrl.clear();
      _sortTasks();
    });
    _saveTasks();
  }

  void _toggleCompleted(int index, bool? value) {
    setState(() {
      _tasks[index].completed = value ?? false;
      _sortTasks();
    });
    _saveTasks();
  }

  void _deleteTask(int index) {
    setState(() => _tasks.removeAt(index));
    _saveTasks();
  }

  Future<void> _editPriorityDialog(int index) async {
    Priority selected = _tasks[index].priority;
    final result = await showDialog<Priority>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Priority'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: Priority.values.map((p) {
              return RadioListTile<Priority>(
                value: p,
                groupValue: selected,
                onChanged: (val) => setState(() => selected = val!),
                title: Text(p.label),
              );
            }).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null && result != _tasks[index].priority) {
      setState(() {
        _tasks[index].priority = result;
        _sortTasks();
      });
      _saveTasks();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task priority changed to ${result.label}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Manager'),
        actions: [
          Row(
            children: [
              Icon(widget.isDark ? Icons.dark_mode : Icons.light_mode),
              Switch(
                value: widget.isDark,
                onChanged: (_) => widget.onToggleTheme(),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: TextField(
                    controller: _taskCtrl,
                    onSubmitted: (_) => _addTask(),
                    decoration: const InputDecoration(
                      labelText: 'Task name',
                      hintText: 'What do you need to do?',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: DropdownButtonFormField<Priority>(
                    value: _newTaskPriority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    onChanged: (p) => setState(() => _newTaskPriority = p!),
                    items: Priority.values
                        .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                        .toList(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _addTask,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _tasks.isEmpty
                  ? Center(
                      child: Text(
                        'No tasks yet.\nAdd your first task.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _tasks.length,
                      itemBuilder: (context, index) {
                        return _TaskTile(
                          key: ValueKey(_tasks[index].name + index.toString()),
                          task: _tasks[index],
                          isDark: widget.isDark,
                          onToggle: (v) => _toggleCompleted(index, v),
                          onDelete: () => _deleteTask(index),
                          onEdit: () => _editPriorityDialog(index),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final Task task;
  final bool isDark;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _TaskTile({
    super.key,
    required this.task,
    required this.isDark,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Always-on subtle glow (neutral white or subtle dark shadow)
    final shadowColor = isDark
        ? Colors.white.withOpacity(0.12)
        : Colors.black.withOpacity(0.08);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        leading: Checkbox(
          value: task.completed,
          onChanged: onToggle,
        ),
        title: Text(
          task.name,
          style: TextStyle(
            decoration: task.completed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text('Priority: ${task.priority.label}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}