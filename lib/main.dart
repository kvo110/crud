import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TaskApp());
}

/// Priority levels for tasks (High shows up first).
enum Priority { high, medium, low }

extension PriorityX on Priority {
  String get label {
    switch (this) {
      case Priority.high:
        return 'High';
      case Priority.medium:
        return 'Medium';
      case Priority.low:
        return 'Low';
    }
  }

  /// Lower number = higher priority. Easy to sort.
  int get rank {
    switch (this) {
      case Priority.high:
        return 0;
      case Priority.medium:
        return 1;
      case Priority.low:
        return 2;
    }
  }

  static Priority fromString(String s) {
    switch (s) {
      case 'high':
        return Priority.high;
      case 'medium':
        return Priority.medium;
      case 'low':
      default:
        return Priority.low;
    }
  }

  String get asString {
    switch (this) {
      case Priority.high:
        return 'high';
      case Priority.medium:
        return 'medium';
      case Priority.low:
        return 'low';
    }
  }
}

/// Tiny model: name + done flag + priority.
/// Keeping it simple so setState + JSON save is painless.
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
        name: map['name'] as String? ?? '',
        completed: map['completed'] as bool? ?? false,
        priority: PriorityX.fromString(map['priority'] as String? ?? 'low'),
      );
}

/// App shell only handles theme + persistence for theme.
/// Tasks themselves live in the screen (to show setState usage).
class TaskApp extends StatefulWidget {
  const TaskApp({super.key});
  @override
  State<TaskApp> createState() => _TaskAppState();
}

class _TaskAppState extends State<TaskApp> {
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDark = prefs.getBool('isDark') ?? false);
  }

  Future<void> _saveTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', value);
  }

  void _toggleTheme() {
    setState(() => _isDark = !_isDark);
    _saveTheme(_isDark); // just storing this locally so users don’t have to re-pick their theme every time
  }

  @override
  Widget build(BuildContext context) {
    final light = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    );

    final dark = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'Task Manager',
      debugShowCheckedModeBanner: false,
      theme: _isDark ? dark : light,
      home: TaskListScreen(
        isDark: _isDark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

/// Main screen: basic CRUD with setState, priority, and local save.
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
  final TextEditingController _taskInputCtrl = TextEditingController();
  Priority _newTaskPriority = Priority.medium;
  final String _storageKey = 'tasks_v1';

  List<Task> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final decoded = json.decode(jsonStr) as List<dynamic>;
      _tasks = decoded.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
      _sortTasks();
      setState(() {}); // wake the UI after loading from disk
    }
  }

  Future<void> _persistTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(_tasks.map((t) => t.toJson()).toList());
    await prefs.setString(_storageKey, encoded); // quick local save so stuff sticks between app runs
  }

  /// Sorts so the important stuff floats to the top.
  /// Order: High → Medium → Low, then incomplete → complete, then alphabetically.
  void _sortTasks() {
    _tasks.sort((a, b) {
      final byPriority = a.priority.rank.compareTo(b.priority.rank);
      if (byPriority != 0) return byPriority;

      final byCompleted = (a.completed ? 1 : 0).compareTo(b.completed ? 1 : 0); // false (0) before true (1)
      if (byCompleted != 0) return byCompleted;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  Future<void> _addTask() async {
    final text = _taskInputCtrl.text.trim();
    if (text.isEmpty) return; // ignore empty adds; user likely hit enter by accident
    setState(() {
      _tasks.add(Task(name: text, priority: _newTaskPriority));
      _taskInputCtrl.clear();
      _sortTasks();
    });
    await _persistTasks();
  }

  Future<void> _toggleCompleted(int index, bool? value) async {
    setState(() {
      _tasks[index].completed = value ?? false;
      _sortTasks(); // keep done items from cluttering the top
    });
    await _persistTasks();
  }

  Future<void> _deleteTask(int index) async {
    setState(() => _tasks.removeAt(index)); // simple and direct
    await _persistTasks();
  }

  Future<void> _updatePriority(int index, Priority p) async {
    setState(() {
      _tasks[index].priority = p;
      _sortTasks(); // re-rank immediately so the list feels responsive
    });
    await _persistTasks();
  }

  /// Quick rename dialog — handy for typos without building a whole edit screen.
  Future<void> _renameTask(int index) async {
    final controller = TextEditingController(text: _tasks[index].name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter new name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.of(context).pop(val.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      setState(() {
        _tasks[index].name = newName;
        _sortTasks();
      });
      await _persistTasks();
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
              // global theme toggle; saved so it doesn’t reset every launch
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
          // New task input row: name + priority + add button.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: TextField(
                    controller: _taskInputCtrl,
                    onSubmitted: (_) => _addTask(),
                    decoration: const InputDecoration(
                      labelText: 'Task name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Priority>(
                        isExpanded: true,
                        value: _newTaskPriority,
                        onChanged: (p) {
                          if (p != null) setState(() => _newTaskPriority = p); // keep whatever they pick for the next add
                        },
                        items: Priority.values
                            .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                            .toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _addTask,
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 0),
          Expanded(
            child: _tasks.isEmpty
                ? Center(
                    child: Text(
                      'No tasks yet.\nAdd your first task!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: _tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final task = _tasks[index];

                      return Material(
                        elevation: 1,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: Checkbox(
                            value: task.completed,
                            onChanged: (v) => _toggleCompleted(index, v),
                          ),
                          title: Text(
                            task.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            // strike-through when done — simple visual win
                            style: task.completed
                                ? const TextStyle(decoration: TextDecoration.lineThrough)
                                : null,
                          ),
                          subtitle: Row(
                            children: [
                              _PriorityChip(priority: task.priority),
                              if (task.completed) const SizedBox(width: 8),
                              if (task.completed) const Icon(Icons.check_circle, size: 16),
                            ],
                          ),
                          // tap-to-rename is faster than editing in a separate screen
                          onTap: () => _renameTask(index),
                          // trailing lets us adjust priority after creation and delete quickly
                          trailing: SizedBox(
                            width: 170,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                DropdownButton<Priority>(
                                  value: task.priority,
                                  onChanged: (p) {
                                    if (p != null) _updatePriority(index, p);
                                  },
                                  items: Priority.values
                                      .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                                      .toList(),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () => _deleteTask(index),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Little label for priority level; color is just a hint.
/// Not using error colors so people don’t think something is broken.
class _PriorityChip extends StatelessWidget {
  final Priority priority;
  const _PriorityChip({required this.priority});

  @override
  Widget build(BuildContext context) {
    final Color tone;
    switch (priority) {
      case Priority.high:
        tone = Colors.redAccent;
        break;
      case Priority.medium:
        tone = Colors.amber;
        break;
      case Priority.low:
        tone = Colors.green;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withOpacity(0.55)),
      ),
      child: Text(
        priority.label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: tone,
          fontSize: 12,
        ),
      ),
    );
  }
}