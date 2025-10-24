import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
// --- For CSV Export and Permissions ---
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DebtLedgerApp());
}

// --- NEW FEATURE: LIVE AMOUNT FORMATTING ---
// This class automatically formats the input with commas (Indian style).
class IndianCurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    // Remove all non-digit characters
    String newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (newText.isEmpty) return const TextEditingValue();

    double value = double.parse(newText);
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 0);
    String formattedText = formatter.format(value);

    return newValue.copyWith(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}


class DebtLedgerApp extends StatelessWidget {
  const DebtLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // --- NEW THEME: REFRESHING AND LIGHT ---
    const primaryColor = Colors.teal;

    return MaterialApp(
      title: 'DebtLedger',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: primaryColor,
        scaffoldBackgroundColor: const Color(0xFFF7F9FA), // A very light grey
        cardColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
          primary: primaryColor,
          secondary: Colors.teal.shade300,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: primaryColor,
          unselectedItemColor: Colors.grey,
        ),
      ),
      home: const LockScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Lock Screen ---
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  final TextEditingController pinController = TextEditingController();
  String? _errorMessage;
  bool _isBiometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricsAndAutoUnlock();
  }

  Future<void> _checkBiometricsAndAutoUnlock() async {
    final canCheck = await auth.canCheckBiometrics;
    final isDeviceSupported = await auth.isDeviceSupported();
    if (mounted) {
      setState(() {
        _isBiometricAvailable = canCheck && isDeviceSupported;
      });
    }
    if (_isBiometricAvailable) {
      _authenticateWithBiometrics();
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: 'Unlock DebtLedger with your fingerprint or face',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (authenticated && mounted) {
        _navigateToMain();
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Biometric error: ${e.message}');
      }
    }
  }

  Future<void> _validatePin() async {
    String? storedPin = await storage.read(key: 'app_pin');
    if (storedPin == null) {
      _showSetPinDialog();
      return;
    }
    if (pinController.text == storedPin) {
      _navigateToMain();
    } else {
      setState(() {
        _errorMessage = 'Invalid PIN';
        pinController.clear();
      });
    }
  }

  void _navigateToMain() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const AppLifecycleWrapper(child: MainPage())),
    );
  }

  void _showSetPinDialog() {
    TextEditingController newPinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set New PIN'),
        content: TextField(
          controller: newPinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'Enter a 4-digit PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (newPinController.text.length == 4) {
                final navigator = Navigator.of(context);
                await storage.write(key: 'app_pin', value: newPinController.text);
                if (!mounted) return;
                navigator.pop();
                _navigateToMain();
              }
            },
            child: const Text('Set & Login'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_rounded, size: 80, color: Theme.of(context).primaryColor),
              const SizedBox(height: 24),
              const Text('DebtLedger', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87)),
              const Text('Secure & Simple', style: TextStyle(fontSize: 16, color: Colors.black54)),
              const SizedBox(height: 48),
              if (_isBiometricAvailable)
                OutlinedButton.icon(
                  onPressed: _authenticateWithBiometrics,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock with Biometrics'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).primaryColor,
                      minimumSize: const Size(200, 50),
                      side: BorderSide(color: Theme.of(context).primaryColor)
                  ),
                ),
              const SizedBox(height: 24),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 16, color: Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Enter PIN',
                  counterText: "",
                ),
                onSubmitted: (_) => _validatePin(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _validatePin, style: ElevatedButton.styleFrom(minimumSize: const Size(200, 50)), child: const Text('Login')),
              TextButton(onPressed: _showSetPinDialog, child: const Text('No PIN? Set one now')),
            ],
          ),
        ),
      ),
    );
  }
}

// --- AppLifecycleWrapper ---
class AppLifecycleWrapper extends StatefulWidget {
  final Widget child;
  const AppLifecycleWrapper({super.key, required this.child});
  @override
  State<AppLifecycleWrapper> createState() => _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends State<AppLifecycleWrapper> with WidgetsBindingObserver {
  bool _obscureScreen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    setState(() {
      _obscureScreen = state == AppLifecycleState.inactive || state == AppLifecycleState.paused;
    });
  }
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_obscureScreen)
          Scaffold(
            body: Center(
              child: Icon(Icons.shield_rounded, size: 80, color: Theme.of(context).primaryColor),
            ),
          ),
      ],
    );
  }
}

// --- Data Model and Database Helper ---
class Transaction {
  final int? id;
  final DateTime date;
  final String personName;
  final double amount;
  final String category;
  final String modeOfTransaction;
  final String remarks;
  final bool isRecurringSetup;
  final double recurringAmount;
  final int recurringDayOfMonth; // 32 will represent "Last Day"
  final String? lastRecurringDate;
  final int? parentTransactionId;

  Transaction({ this.id, required this.date, required this.personName, required this.amount, required this.category, this.modeOfTransaction = 'Other', this.remarks = '', this.isRecurringSetup = false, this.recurringAmount = 0.0, this.recurringDayOfMonth = 1, this.lastRecurringDate, this.parentTransactionId });
  Map<String, dynamic> toMap() => { 'id': id, 'date': date.toIso8601String(), 'personName': personName.trim(), 'amount': amount, 'category': category, 'modeOfTransaction': modeOfTransaction, 'remarks': remarks, 'isRecurringSetup': isRecurringSetup ? 1 : 0, 'recurringAmount': recurringAmount, 'recurringDayOfMonth': recurringDayOfMonth, 'lastRecurringDate': lastRecurringDate, 'parentTransactionId': parentTransactionId };
  factory Transaction.fromMap(Map<String, dynamic> map) => Transaction( id: map['id'], date: DateTime.parse(map['date']), personName: map['personName'], amount: map['amount']?.toDouble() ?? 0.0, category: map['category'], modeOfTransaction: map['modeOfTransaction'] ?? 'Other', remarks: map['remarks'] ?? '', isRecurringSetup: map['isRecurringSetup'] == 1, recurringAmount: map['recurringAmount']?.toDouble() ?? 0.0, recurringDayOfMonth: map['recurringDayOfMonth'] ?? 1, lastRecurringDate: map['lastRecurringDate'], parentTransactionId: map['parentTransactionId'] );
  Transaction copyWith({ int? id, bool? isRecurringSetup, String? lastRecurringDate }) => Transaction( id: id ?? this.id, date: date, personName: personName, amount: amount, category: category, modeOfTransaction: modeOfTransaction, remarks: remarks, isRecurringSetup: isRecurringSetup ?? this.isRecurringSetup, recurringAmount: recurringAmount, recurringDayOfMonth: recurringDayOfMonth, lastRecurringDate: lastRecurringDate ?? this.lastRecurringDate, parentTransactionId: parentTransactionId );
}

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();
  static Database? _database;
  Future<Database> get database async => _database ??= await _initDb();
  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'debtledger.db');
    return await openDatabase(path, version: 3, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }
  Future<void> _onCreate(Database db, int version) async => await _createTables(db);
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      var isRecurringSetupExists = false;
      try {
        await db.rawQuery('SELECT isRecurringSetup FROM transactions LIMIT 1');
        isRecurringSetupExists = true;
      } catch(e) { /* Column doesn't exist */ }

      if (!isRecurringSetupExists) {
        await db.execute('ALTER TABLE transactions ADD COLUMN isRecurringSetup INTEGER NOT NULL DEFAULT 0');
        await db.execute('ALTER TABLE transactions ADD COLUMN recurringAmount REAL NOT NULL DEFAULT 0.0');
        await db.execute('ALTER TABLE transactions ADD COLUMN recurringDayOfMonth INTEGER NOT NULL DEFAULT 1');
        await db.execute('ALTER TABLE transactions ADD COLUMN lastRecurringDate TEXT');
        await db.execute('ALTER TABLE transactions ADD COLUMN parentTransactionId INTEGER');
      }
    }
  }
  Future<void> _createTables(Database db) async => await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, personName TEXT NOT NULL, amount REAL NOT NULL, category TEXT NOT NULL, modeOfTransaction TEXT NOT NULL, remarks TEXT, isRecurringSetup INTEGER NOT NULL DEFAULT 0, recurringAmount REAL NOT NULL DEFAULT 0.0, recurringDayOfMonth INTEGER NOT NULL DEFAULT 1, lastRecurringDate TEXT, parentTransactionId INTEGER)');
  Future<int> addTransaction(Transaction transaction) async => (await database).insert('transactions', transaction.toMap());
  Future<int> updateTransaction(Transaction transaction) async => (await database).update('transactions', transaction.toMap(), where: 'id = ?', whereArgs: [transaction.id]);
  Future<int> deleteTransaction(int id) async => (await database).delete('transactions', where: 'id = ?', whereArgs: [id]);
  Future<List<Transaction>> getAllTransactions() async => (await database).query('transactions', orderBy: 'date DESC').then((maps) => List.generate(maps.length, (i) => Transaction.fromMap(maps[i])));
  Future<void> clearAllTransactions() async => (await database).delete('transactions');
}


// --- PHASE 2: NEW NAVIGATION STRUCTURE ---
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Transaction> _transactions = [];
  Map<String, double> _accountBalances = {};

  @override
  void initState() {
    super.initState();
    _processAndRefreshData();
    // --- NEW: Check if an automatic backup is due ---
    _checkForAutomaticBackup();
  }

  // --- NEW: AUTOMATIC BACKUP LOGIC ---
  Future<void> _checkForAutomaticBackup() async {
    final storage = const FlutterSecureStorage();
    String? lastBackupTimestampStr = await storage.read(key: 'last_auto_backup_timestamp');
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));

    if (lastBackupTimestampStr != null) {
      final lastBackupDate = DateTime.parse(lastBackupTimestampStr);
      if (lastBackupDate.isAfter(sevenDaysAgo)) {
        // Backup is recent enough, do nothing.
        return;
      }
    }

    // Use a post-frame callback to ensure context is available for SnackBar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted) _performAutomaticBackup(context);
    });
  }

  Future<void> _performAutomaticBackup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final storage = const FlutterSecureStorage();
    try {
      final transactions = await _dbHelper.getAllTransactions();
      if (transactions.isEmpty) return; // No data to back up

      final pin = await storage.read(key: 'app_pin');
      if (pin == null) return; // Cannot backup without a PIN to use as a password

      final jsonData = jsonEncode(transactions.map((tx) => tx.toMap()).toList());
      final key = encrypt.Key.fromUtf8(pin.padRight(32).substring(0, 32));
      final iv = encrypt.IV.fromLength(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      final encrypted = encrypter.encrypt(jsonData, iv: iv);

      final directory = await getApplicationDocumentsDirectory();
      
      // --- MODIFICATION: Delete all previous auto-backups before creating a new one ---
      final allFiles = directory.listSync();
      final oldAutoBackups = allFiles.where((f) => f.path.contains('debtledger_auto_backup_'));
      for (final oldFile in oldAutoBackups) {
        await oldFile.delete();
      }

      final path = '${directory.path}/debtledger_auto_backup_${DateFormat('yyyyMMdd').format(DateTime.now())}.enc';
      final file = File(path);
      await file.writeAsString('${iv.base64}\n${encrypted.base64}');

      await storage.write(key: 'last_auto_backup_timestamp', value: DateTime.now().toIso8601String());
      messenger.showSnackBar(const SnackBar(content: Text("Automatic weekly backup completed.")));
    } catch (e) {
      // Silently fail, but print for debugging.
      debugPrint("Automatic backup failed: $e");
    }
  }
  // --- END: AUTOMATIC BACKUP LOGIC ---

  Future<void> _processAndRefreshData() async {
    await _processRecurringTransactions();
    await _refreshData();
  }

  Future<void> _refreshData() async {
    final data = await _dbHelper.getAllTransactions();
    if (mounted) {
      setState(() {
        _transactions = data;
        _calculateTotals();
      });
    }
  }

  void _calculateTotals() {
    final balances = <String, double>{};
    // Sort transactions by date to ensure correct balance calculation
    _transactions.sort((a, b) => a.date.compareTo(b.date));

    for (var txn in _transactions) {
      // These categories increase the balance (the person owes you more, or you owe them less)
      const creditCategories = ['You Lent', 'You Paid Back', 'Interest Charged'];
      
      final amount = creditCategories.contains(txn.category) ? txn.amount : -txn.amount;
      balances.update(txn.personName, (v) => v + amount, ifAbsent: () => amount);
    }
    if (mounted) {
      setState(() { _accountBalances = balances; });
    }
  }

  Future<void> _processRecurringTransactions() async {
    final allTxns = await _dbHelper.getAllTransactions();
    final recurringTxns = allTxns.where((tx) => tx.isRecurringSetup).toList();
    final now = DateTime.now();

    for(final parentTx in recurringTxns) {
      DateTime lastPosted = parentTx.lastRecurringDate != null
          ? DateTime.parse(parentTx.lastRecurringDate!)
          : parentTx.date;

      DateTime getNextDueDate(DateTime afterDate) {
        DateTime potentialDueDate;
        if (parentTx.recurringDayOfMonth > 31) {
          potentialDueDate = DateTime(afterDate.year, afterDate.month + 1, 0);
        } else {
          int lastDayCurrentMonth = DateTime(afterDate.year, afterDate.month + 1, 0).day;
          potentialDueDate = DateTime(afterDate.year, afterDate.month, min(parentTx.recurringDayOfMonth, lastDayCurrentMonth));
        }
        if (potentialDueDate.isBefore(afterDate) || potentialDueDate.day == afterDate.day) {
            var nextMonthDate = DateTime(afterDate.year, afterDate.month + 1, 1);
            if (parentTx.recurringDayOfMonth > 31) {
                return DateTime(nextMonthDate.year, nextMonthDate.month + 1, 0);
            } else {
                int lastDayNextMonth = DateTime(nextMonthDate.year, nextMonthDate.month + 1, 0).day;
                return DateTime(nextMonthDate.year, nextMonthDate.month, min(parentTx.recurringDayOfMonth, lastDayNextMonth));
            }
        }
        return potentialDueDate;
      }

      DateTime nextDueDate = getNextDueDate(lastPosted);
      
      while(nextDueDate.isBefore(now) || nextDueDate.isAtSameMomentAs(now)) {
        bool alreadyExists = allTxns.any((tx) => tx.parentTransactionId == parentTx.id && tx.date.year == nextDueDate.year && tx.date.month == nextDueDate.month && tx.date.day == nextDueDate.day);
        
        if (!alreadyExists) {
          // --- FIX: Use new category system ---
          String newCategory = parentTx.category == 'You Lent' ? 'Interest Charged' : 'Interest Incurred';
          final newAutoTx = Transaction(personName: parentTx.personName, amount: parentTx.recurringAmount, category: newCategory, date: nextDueDate, remarks: 'Recurring Entry for ${DateFormat.yMMMM().format(nextDueDate)}', parentTransactionId: parentTx.id);
          await _dbHelper.addTransaction(newAutoTx);
          final updatedParent = parentTx.copyWith(lastRecurringDate: nextDueDate.toIso8601String());
          await _dbHelper.updateTransaction(updatedParent);
          allTxns.add(newAutoTx);
        }
        lastPosted = nextDueDate;
        nextDueDate = getNextDueDate(lastPosted);
      }
    }
  }

  Future<void> _showExitDialog() async {
    final bool shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text('Exit App'),
                content: const Text('Are you sure you want to exit?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('No')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Yes'))
                ])) ??
        false;
    if (shouldPop) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(
        accountBalances: _accountBalances,
        onRefresh: _processAndRefreshData,
      ),
      AccountsScreen(
        accountBalances: _accountBalances,
        onRefresh: _processAndRefreshData,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) return;
        _showExitDialog();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: screens,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Accounts'),
          ],
        ),
      ),
    );
  }
}


// --- NEW: DASHBOARD SCREEN WITH BAR CHARTS & ENGAGING EMPTY STATE ---
class DashboardScreen extends StatelessWidget {
  final Map<String, double> accountBalances;
  final Future<void> Function() onRefresh;

  const DashboardScreen({
    super.key,
    required this.accountBalances,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final double totalGiven = accountBalances.values.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    final double totalTaken = accountBalances.values.where((v) => v < 0).fold(0.0, (a, b) => a + b).abs();
    
    Future<void> navigateToTransactionPage({bool isRecurring = false}) async {
      final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => TransactionPage(
          isRecurring: isRecurring,
          accountBalances: accountBalances,
          existingPersons: accountBalances.keys.toList()
      )));
      if (result == true) {
        onRefresh();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () => _showSettingsDialog(context, onRefresh))],
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: accountBalances.isEmpty
        ? _buildEmptyState(context, () => navigateToTransactionPage())
        : ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildDashboardSummary(totalGiven, totalTaken),
            const SizedBox(height: 24),
            _buildActionMenu(context,
              onAddTransaction: () => navigateToTransactionPage(),
              onAddRecurring: () => navigateToTransactionPage(isRecurring: true),
              onShowReports: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportsPage(dbHelper: DatabaseHelper()))),
            ),
            const SizedBox(height: 24),
            Text('Financial Overview', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _buildBarCharts(context, accountBalances),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, VoidCallback onAddTransaction) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text("Your ledger is empty.", style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 8),
          const Text("Add a transaction to get started.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onAddTransaction,
            child: const Text('Add First Transaction'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardSummary(double totalGiven, double totalTaken) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildDashboardItem("You Are Owed", totalGiven, Colors.green.shade700),
            _buildDashboardItem("You Owe", totalTaken, Colors.red.shade700),
            _buildDashboardItem("Net Balance", totalGiven - totalTaken, (totalGiven - totalTaken) >= 0 ? Colors.green.shade700 : Colors.red.shade700),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardItem(String title, double amount, Color color) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 14, color: Colors.black54)),
        const SizedBox(height: 4),
        Text(
          NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2).format(amount),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildActionMenu(BuildContext context, {required VoidCallback onAddTransaction, required VoidCallback onAddRecurring, required VoidCallback onShowReports}) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.center,
      children: [
        ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Add Transaction'), onPressed: onAddTransaction),
        ElevatedButton.icon(icon: const Icon(Icons.repeat), label: const Text('Add Recurring Payment'), onPressed: onAddRecurring),
        ElevatedButton.icon(icon: const Icon(Icons.assessment), label: const Text('View Reports'), onPressed: onShowReports),
      ],
    );
  }

  Widget _buildBarCharts(BuildContext context, Map<String, double> balances) {
    final owedToYou = Map.fromEntries(balances.entries.where((e) => e.value > 0));
    final youOwe = Map.fromEntries(balances.entries.where((e) => e.value < 0).map((e) => MapEntry(e.key, e.value.abs())));

    return Column(
      children: [
        _buildBarChartCard(context, "Top 5 You Are Owed", owedToYou, Colors.green),
        const SizedBox(height: 16),
        _buildBarChartCard(context, "Top 5 You Owe", youOwe, Colors.red),
      ],
    );
  }
  
  Widget _buildBarChartCard(BuildContext context, String title, Map<String, double> data, Color color) {
    if (data.isEmpty) {
      return const SizedBox.shrink(); // Don't show the card if there's no data
    }

    final sortedData = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sortedData.take(5);
    final maxValue = top5.isEmpty ? 1.0 : top5.first.value;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ...top5.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(entry.value),
                          style: TextStyle(color: color, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: entry.value / maxValue,
                        minHeight: 8,
                        backgroundColor: color.withAlpha((255 * 0.2).round()),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// --- ACCOUNTS SCREEN WITH SORTING ---
enum SortOption { byName, byOwedToYou, byYouOwe }

class AccountsScreen extends StatefulWidget {
  final Map<String, double> accountBalances;
  final Future<void> Function() onRefresh;

  const AccountsScreen({super.key, required this.accountBalances, required this.onRefresh});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final TextEditingController _searchController = TextEditingController();
  Map<String, double> _filteredBalances = {};
  SortOption _currentSortOption = SortOption.byName;

  @override
  void initState() {
    super.initState();
    _filteredBalances = widget.accountBalances;
    _searchController.addListener(_filterAccounts);
  }
  
  @override
  void didUpdateWidget(covariant AccountsScreen oldWidget) {
      super.didUpdateWidget(oldWidget);
      if (widget.accountBalances != oldWidget.accountBalances) {
          _filterAccounts();
      }
  }

  void _filterAccounts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredBalances = widget.accountBalances;
      } else {
        _filteredBalances = Map.fromEntries(
          widget.accountBalances.entries.where((entry) => entry.key.toLowerCase().contains(query))
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sortedAccounts = _filteredBalances.entries.toList();
    
    switch (_currentSortOption) {
      case SortOption.byName:
        sortedAccounts.sort((a, b) => a.key.compareTo(b.key));
        break;
      case SortOption.byOwedToYou:
        sortedAccounts.sort((a, b) => b.value.compareTo(a.value));
        break;
      case SortOption.byYouOwe:
        sortedAccounts.sort((a, b) => a.value.compareTo(b.value));
        break;
    }
    
    return Scaffold(
      appBar: AppBar(title: const Text('All Accounts')),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search Accounts',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear())
                      : null,
                ),
              ),
            ),
            _buildSortControls(),
            Expanded(
              child: sortedAccounts.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text("No accounts found.", style: TextStyle(fontSize: 18, color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: sortedAccounts.length,
                      itemBuilder: (context, index) {
                        final account = sortedAccounts[index];
                        final balance = account.value;
                        final color = balance >= 0 ? Colors.green.shade700 : Colors.red.shade700;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                          child: ListTile(
                            leading: _buildAvatar(account.key),
                            title: Text(account.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: Text(
                              NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2).format(balance.abs()),
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            onTap: () async {
                              final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => PersonLedgerPage(personName: account.key)));
                              if(result == true) {
                                widget.onRefresh();
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 8.0,
        children: [
          ChoiceChip(
            label: const Text('By Name'),
            selected: _currentSortOption == SortOption.byName,
            onSelected: (selected) {
              if (selected) setState(() => _currentSortOption = SortOption.byName);
            },
          ),
          ChoiceChip(
            label: const Text('Owed to You'),
            selected: _currentSortOption == SortOption.byOwedToYou,
            onSelected: (selected) {
              if (selected) setState(() => _currentSortOption = SortOption.byOwedToYou);
            },
          ),
          ChoiceChip(
            label: const Text('You Owe'),
            selected: _currentSortOption == SortOption.byYouOwe,
            onSelected: (selected) {
              if (selected) setState(() => _currentSortOption = SortOption.byYouOwe);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String name) {
    return CircleAvatar(
      backgroundColor: _getColorForName(name),
      child: Text(_getInitials(name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '';
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
    } else {
      return parts[0][0].toUpperCase();
    }
  }

  Color _getColorForName(String name) {
    final colors = [Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple, Colors.teal, Colors.indigo, Colors.brown];
    return colors[name.hashCode % colors.length];
  }
}

// --- SHARED SETTINGS DIALOG (WITH IMPORT CSV) ---
void _showSettingsDialog(BuildContext context, Future<void> Function() onRefresh) {
  final storage = const FlutterSecureStorage();
  final dbHelper = DatabaseHelper();

  Future<void> restoreData() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.single.path == null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No file selected.")));
        return;
      }
      if(!result.files.single.path!.endsWith('.enc')){
        if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid file type. Please select a .enc file.")));
        return;
      }
      final passphraseController = TextEditingController();
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore Passphrase'),
          content: TextField(
            controller: passphraseController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Enter passphrase to decrypt'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (passphraseController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passphrase cannot be empty.')));
                } else {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final file = File(result.files.single.path!);
      final content = await file.readAsLines();
      if (content.length < 2) throw Exception('Invalid backup file format.');
      final iv = encrypt.IV.fromBase64(content[0]);
      final encryptedData = content[1];
      final key = encrypt.Key.fromUtf8(passphraseController.text.padRight(32).substring(0, 32));
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      final decrypted = encrypter.decrypt64(encryptedData, iv: iv);
      final List<dynamic> jsonMaps = jsonDecode(decrypted);
      final transactionsToRestore = jsonMaps.map((map) => Transaction.fromMap(map as Map<String, dynamic>)).toList();
      await dbHelper.clearAllTransactions();
      for (var tx in transactionsToRestore) {
        await dbHelper.addTransaction(tx);
      }
      await onRefresh();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data restored successfully.")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Restore failed. Check passphrase or file. Error: $e")));
    }
  }

  Future<void> backupData() async {  
    final passphraseController = TextEditingController();
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup Passphrase'),
        content: TextField(
          controller: passphraseController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Enter a password to encrypt backup'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (passphraseController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passphrase cannot be empty.')));
              } else {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Backup'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final transactions = await dbHelper.getAllTransactions();
      if (!context.mounted) return;
      if (transactions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to backup.")));
        return;
      }
      final jsonData = jsonEncode(transactions.map((tx) => tx.toMap()).toList());
      final key = encrypt.Key.fromUtf8(passphraseController.text.padRight(32).substring(0, 32));
      final iv = encrypt.IV.fromLength(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      final encrypted = encrypter.encrypt(jsonData, iv: iv);
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/debtledger_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.enc';
      final file = File(path);
      await file.writeAsString('${iv.base64}\n${encrypted.base64}');
      await Share.shareXFiles([XFile(path)], text: 'DebtLedger Encrypted Backup');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Backup failed: $e")));
    }
   }
  void showChangePinDialog() {  
    final newPinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set New PIN'),
        content: TextField(
          controller: newPinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'Enter a 4-digit PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (newPinController.text.length == 4) {
                final navigator = Navigator.of(context);
                
                await storage.write(key: 'app_pin', value: newPinController.text);
                if (!context.mounted) return;
                navigator.pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN updated successfully.')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
   }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.lock_reset), title: const Text('Change PIN'), onTap: () { Navigator.pop(context); showChangePinDialog(); }),
          ListTile(leading: const Icon(Icons.backup), title: const Text('Encrypted Backup'), onTap: () { Navigator.pop(context); backupData(); }),
          ListTile(leading: const Icon(Icons.restore), title: const Text('Restore Backup'), onTap: () { Navigator.pop(context); restoreData(); }),
          // --- NEW: IMPORT FROM CSV ---
          ListTile(
            leading: const Icon(Icons.upload_file), 
            title: const Text('Import from CSV'), 
            onTap: () async {  
              Navigator.pop(context);  
              final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => const ImportCsvPage()));
              if (result == true) {
                onRefresh();
              }
            }
          ),
          ListTile(leading: const Icon(Icons.help_outline), title: const Text('Help / User Guide'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const HelpPage())); }),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_open),
            title: const Text('Disable PIN'),
            subtitle: const Text('Removes app lock'),
            onTap: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              await storage.delete(key: 'app_pin');
              navigator.pop();
              messenger.showSnackBar(const SnackBar(content: Text('PIN disabled.')));
            },
          ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ),
  );
}

// --- PersonLedgerPage WITH HEADER & IMPROVED EMPTY STATE ---
class PersonLedgerPage extends StatefulWidget {
  final String personName;
  const PersonLedgerPage({super.key, required this.personName});
  @override
  PersonLedgerPageState createState() => PersonLedgerPageState();
}

class PersonLedgerPageState extends State<PersonLedgerPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Transaction> _personTransactions = [];
  double _currentBalance = 0.0;
  Map<String, double> _accountBalances = {}; // To pass to transaction page

  @override
  void initState() {
    super.initState();
    _refreshPersonData();
  }

  Future<void> _refreshPersonData() async {
    final allTx = await _dbHelper.getAllTransactions();
    allTx.sort((a,b) => a.date.compareTo(b.date)); // Sort chronologically for accurate calculations
    final personTx = allTx.where((tx) => tx.personName == widget.personName).toList();
    
    // Recalculate all balances to pass the correct map to the edit page
    final balances = <String, double>{};
    for (var txn in allTx) {
      const creditCategories = ['You Lent', 'You Paid Back', 'Interest Charged'];
      final amount = creditCategories.contains(txn.category) ? txn.amount : -txn.amount;
      balances.update(txn.personName, (v) => v + amount, ifAbsent: () => amount);
    }

    if (mounted) {
      setState(() { 
        // Reverse the list for display purposes (newest first)
        _personTransactions = personTx.reversed.toList(); 
        _currentBalance = balances[widget.personName] ?? 0.0;
        _accountBalances = balances;
      });
    }
  }

  Future<void> _navigateToTransactionPage({Transaction? transaction}) async {
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionPage(
          transaction: transaction,
          isRecurring: transaction?.isRecurringSetup ?? false,
          existingPersons: _accountBalances.keys.toList(),
          accountBalances: _accountBalances,
          initialPersonName: widget.personName,
        ),
      ),
    );
    if(result == true) {
      _refreshPersonData();
    }
  }
  
  // Helper methods for avatar, copied from AccountsScreen
  Widget _buildAvatar(String name) {
    return CircleAvatar(
      backgroundColor: _getColorForName(name),
      child: Text(_getInitials(name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '';
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
    } else {
      return parts[0][0].toUpperCase();
    }
  }

  Color _getColorForName(String name) {
    final colors = [Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple, Colors.teal, Colors.indigo, Colors.brown];
    return colors[name.hashCode % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) return;
        Navigator.pop(context, true); // Signal that a refresh might be needed
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.personName),
        ),
        body: Column(
          children: [
            _buildSummaryHeader(),
            Expanded(
              child: _personTransactions.isEmpty
                  ? const Center(child: Text("No transactions for this person yet."))
                  : ListView.builder(
                      itemCount: _personTransactions.length,
                      itemBuilder: (context, index) {
                        final tx = _personTransactions[index];
                        const creditCategories = ['You Lent', 'You Paid Back', 'Interest Charged'];
                        final isCredit = creditCategories.contains(tx.category);
                        final amountColor = isCredit ? Colors.green.shade700 : Colors.red.shade700;
                        
                        if (tx.isRecurringSetup) {
                          final recurringAmountFormatted = NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(tx.recurringAmount);
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.teal.shade50,
                            child: ListTile(
                              leading: const Icon(Icons.repeat, color: Colors.teal),
                              title: const Text("Recurring Payment Setup", style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("EMI: $recurringAmountFormatted / month\nDue on Day ${tx.recurringDayOfMonth == 32 ? 'Last' : tx.recurringDayOfMonth}"),
                              isThreeLine: true,
                              onTap: () => _showTransactionDetails(tx),
                            ),
                          );
                        }
                        final formattedAmount = NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(tx.amount);
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            title: Text(tx.category, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("${DateFormat.yMMMd().format(tx.date)} - ${tx.modeOfTransaction}\n${tx.remarks}"),
                            isThreeLine: tx.remarks.isNotEmpty,
                            trailing: Text("${isCredit ? '+' : '-'} $formattedAmount", style: TextStyle(color: amountColor, fontWeight: FontWeight.bold, fontSize: 16)),
                            onTap: () => _showTransactionDetails(tx),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(onPressed: () => _navigateToTransactionPage(), child: const Icon(Icons.add)),
      ),
    );
  }

  Widget _buildSummaryHeader() {
    final color = _currentBalance >= 0 ? Colors.green.shade700 : Colors.red.shade700;
    final formattedBalance = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2).format(_currentBalance.abs());
    final balanceText = _currentBalance >= 0 ? "Owes you" : "You owe";
    
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            _buildAvatar(widget.personName),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    balanceText,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
                  ),
                  Text(
                    formattedBalance,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 24),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showTransactionDetails(Transaction tx) {
    const creditCategories = ['You Lent', 'You Paid Back', 'Interest Charged'];
    final isCredit = creditCategories.contains(tx.category);
    final amountColor = isCredit ? Colors.green.shade700 : Colors.red.shade700;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Transaction Details', style: Theme.of(context).textTheme.titleLarge),
              const Divider(height: 24),
              if(tx.isRecurringSetup) ...[
                _buildDetailRow('Type:', 'Recurring Payment Setup'),
                _buildDetailRow('Recurring Amount:', NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(tx.recurringAmount)),
                _buildDetailRow('Due Day:', 'Day ${tx.recurringDayOfMonth == 32 ? "Last" : tx.recurringDayOfMonth} of month'),
                _buildDetailRow('First EMI after:', DateFormat.yMMMd().format(tx.date)),
              ] else ...[
                _buildDetailRow('Category:', tx.category),
                _buildDetailRow('Amount:', "${isCredit ? '+' : '-'} ${NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(tx.amount)}", textColor: amountColor),
                _buildDetailRow('Date:', DateFormat.yMMMd().format(tx.date)),
                _buildDetailRow('Mode:', tx.modeOfTransaction),
              ],
              if (tx.remarks.isNotEmpty) _buildDetailRow('Remarks:', tx.remarks),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    onPressed: () { Navigator.pop(context); _confirmDeleteTransaction(tx); },
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                    onPressed: () { Navigator.pop(context); _navigateToTransactionPage(transaction: tx); },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(width: 16),
          Expanded(child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontSize: 16, color: textColor ?? Colors.black87))),
        ],
      ),
    );
  }

  void _confirmDeleteTransaction(Transaction tx) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this transaction? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              await _dbHelper.deleteTransaction(tx.id!);
              _refreshPersonData();
              if(mounted) {
                // Return true to signal a change was made
                Navigator.maybePop(context, true);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

// --- TransactionPage (WITH AUTOCOMPLETE & DYNAMIC CATEGORIES) ---
class TransactionPage extends StatefulWidget {
  final Transaction? transaction;
  final bool isRecurring;
  final List<String> existingPersons;
  final Map<String, double> accountBalances;
  final String? initialPersonName;

  const TransactionPage({ super.key, this.transaction, this.isRecurring = false, required this.existingPersons, required this.accountBalances, this.initialPersonName });

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

enum InterestDirection { charged, incurred }

class _TransactionPageState extends State<TransactionPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _amountController;
  late TextEditingController _remarksController;
  late TextEditingController _recurringAmountController;
  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  String _selectedMode = 'Cash';
  bool _isRecurringSetup = false;
  int _recurringDay = 1;

  // New state for dynamic form
  bool _isExistingPerson = false;
  InterestDirection _interestDirection = InterestDirection.charged;


  bool get isEditMode => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.transaction;

    _isRecurringSetup = widget.isRecurring || tx?.isRecurringSetup == true;
    _nameController = TextEditingController(text: widget.initialPersonName ?? tx?.personName);
    _remarksController = TextEditingController(text: tx?.remarks);
    
    // Check if the initial name is an existing person
    if (_nameController.text.isNotEmpty && widget.existingPersons.contains(_nameController.text)) {
      _isExistingPerson = true;
    }
    
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 0);
    _amountController = TextEditingController(text: (tx != null && tx.amount > 0) ? currencyFormat.format(tx.amount) : '');
    _recurringAmountController = TextEditingController(text: (tx != null && tx.recurringAmount > 0) ? currencyFormat.format(tx.recurringAmount) : '');

    if (tx != null) {
      _selectedDate = tx.date;
      _selectedMode = tx.modeOfTransaction;
      _recurringDay = tx.recurringDayOfMonth;

      // Set initial category for edit mode
      if (['Interest Charged', 'Interest Incurred'].contains(tx.category)) {
          _selectedCategory = 'Add Interest';
          _interestDirection = tx.category == 'Interest Charged' ? InterestDirection.charged : InterestDirection.incurred;
      } else {
          _selectedCategory = tx.category;
      }

    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _remarksController.dispose();
    _recurringAmountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2101));
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() => _selectedDate = pickedDate);
    }
  }

  double _parseCurrency(String text) {
      return double.tryParse(text.replaceAll(',', '')) ?? 0.0;
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final db = DatabaseHelper();
      String finalCategory = _selectedCategory!;

      if (_selectedCategory == 'Add Interest') {
        finalCategory = _interestDirection == InterestDirection.charged ? 'Interest Charged' : 'Interest Incurred';
      }

      final newOrUpdatedTransaction = Transaction(
          id: widget.transaction?.id,
          date: _selectedDate,
          personName: _nameController.text.trim(),
          amount: _isRecurringSetup ? 0.0 : _parseCurrency(_amountController.text),
          category: finalCategory,
          modeOfTransaction: _selectedMode,
          remarks: _remarksController.text,
          isRecurringSetup: _isRecurringSetup,
          recurringAmount: _parseCurrency(_recurringAmountController.text),
          recurringDayOfMonth: _recurringDay,
          lastRecurringDate: _isRecurringSetup ? (isEditMode ? widget.transaction?.lastRecurringDate : _selectedDate.toIso8601String()) : null,
          parentTransactionId: widget.transaction?.parentTransactionId,
      );

      if (isEditMode) {
        await db.updateTransaction(newOrUpdatedTransaction);
      } else {
        await db.addTransaction(newOrUpdatedTransaction);
      }

      if (mounted) Navigator.of(context).pop(true); // Return true to signal a change
    }
  }

  List<String> _getCategoryOptions() {
    if (_isRecurringSetup) {
        return ['You Lent', 'You Borrowed'];
    }
    if (_isExistingPerson) {
        return ['You Lent', 'You Borrowed', 'They Paid You', 'You Paid Back', 'Add Interest'];
    }
    // New person
    return ['You Lent', 'You Borrowed'];
  }

  void _onPersonChanged(String name) {
    setState(() {
      _isExistingPerson = widget.existingPersons.contains(name);
      // Reset category if it's no longer valid
      if (!_getCategoryOptions().contains(_selectedCategory)) {
        _selectedCategory = null;
      }
      // Set intelligent default for interest direction
      double currentBalance = widget.accountBalances[name] ?? 0.0;
      _interestDirection = currentBalance >= 0 ? InterestDirection.charged : InterestDirection.incurred;
    });
  }

  @override
  Widget build(BuildContext context) {
    String title = isEditMode ? 'Edit Entry' : (_isRecurringSetup ? 'Add Recurring Payment' : 'Add Transaction');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isEditMode && widget.transaction!.amount == 0.0)
                SwitchListTile(
                  title: const Text('Recurring Entry?'),
                  value: _isRecurringSetup,
                  onChanged: (bool value) {
                    setState(() { _isRecurringSetup = value; });
                  },
                  secondary: const Icon(Icons.repeat),
                ),
              
              // --- NEW: AUTOCOMPLETE FIELD ---
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _nameController.text),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text == '') {
                    return const Iterable<String>.empty();
                  }
                  return widget.existingPersons.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  _nameController.text = selection;
                  _onPersonChanged(selection);
                },
                fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                  // Use a listener to detect changes for new names
                  textEditingController.addListener(() {
                    _nameController.text = textEditingController.text;
                      _onPersonChanged(textEditingController.text);
                  });
                  return TextFormField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'Person\'s Name'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Please enter a name';
                      if (v.length > 50) return 'Name cannot exceed 50 characters';
                      return null;
                    },
                    enabled: !isEditMode,
                  );
                },
              ),

              if (!_isRecurringSetup) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [IndianCurrencyInputFormatter()],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please enter an amount';
                    if (_parseCurrency(v) <= 0) return 'Amount must be greater than zero';
                    return null;
                  },
                  enabled: widget.transaction?.parentTransactionId == null,
                ),
              ],
              const SizedBox(height: 16),
              
              // --- NEW: DYNAMIC CATEGORY DROPDOWN ---
              if (_nameController.text.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  items: _getCategoryOptions()
                      .map((v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(),
                  onChanged: (widget.transaction?.parentTransactionId != null) ? null : (v) => setState(() => _selectedCategory = v!),
                  decoration: const InputDecoration(labelText: 'Category'),
                  validator: (v) => v == null ? 'Please select a category' : null,
                ),

              // --- NEW: SMART INTEREST TOGGLE ---
              if (_selectedCategory == 'Add Interest')
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Interest Type", style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<InterestDirection>(
                        segments: const <ButtonSegment<InterestDirection>>[
                            ButtonSegment<InterestDirection>(value: InterestDirection.charged, label: Text('Charged to Them'), icon: Icon(Icons.arrow_upward)),
                            ButtonSegment<InterestDirection>(value: InterestDirection.incurred, label: Text('Incurred by You'), icon: Icon(Icons.arrow_downward)),
                        ], 
                        selected: <InterestDirection>{_interestDirection}, 
                        onSelectionChanged: (Set<InterestDirection> newSelection){
                            setState(() {
                              _interestDirection = newSelection.first;
                            });
                        },
                      ),
                    ],
                  ),
                ),

              if (!_isRecurringSetup) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedMode,
                  items: ['Cash', 'Bank Transfer', 'UPI', 'Other'].map((v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setState(() => _selectedMode = v!),
                  decoration: const InputDecoration(labelText: 'Mode of Transaction'),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(controller: _remarksController, decoration: const InputDecoration(labelText: 'Remarks')),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_isRecurringSetup ? 'Start Date for Recurring EMI' : 'Transaction Date'),
                subtitle: Text(DateFormat.yMMMd().format(_selectedDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
              if (_isRecurringSetup)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text('The first EMI will be posted on the next due day after this date.', style: Theme.of(context).textTheme.bodySmall),
                ),
              if (_isRecurringSetup) ...[
                const Divider(height: 24),
                Text("Recurring Details", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _recurringAmountController,
                  decoration: const InputDecoration(labelText: 'Recurring Amount (₹)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [IndianCurrencyInputFormatter()],
                  validator: (v) {
                    if (_isRecurringSetup) {
                      if (v == null || v.isEmpty) return 'Please enter a recurring amount';
                      if (_parseCurrency(v) <= 0) return 'Amount must be greater than zero';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _recurringDay,
                  items: [
                    ...List.generate(31, (index) => index + 1).map((day) => DropdownMenuItem(value: day, child: Text('Day $day of month'))),
                    const DropdownMenuItem(value: 32, child: Text('Last Day of month')),
                  ],
                  onChanged: (value) => setState(() => _recurringDay = value!),
                  decoration: const InputDecoration(labelText: 'Due Day'),
                ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _submitForm,
        label: const Text('Save'),
        icon: const Icon(Icons.save),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}


// --- REPORTS PAGE ---
class ReportsPage extends StatefulWidget {
  final DatabaseHelper dbHelper;
  const ReportsPage({super.key, required this.dbHelper});
  @override
  ReportsPageState createState() => ReportsPageState();
}

class ReportsPageState extends State<ReportsPage> {
  List<Transaction> _allTransactions = [];
  DateTime? _startDate;
  DateTime? _endDate;
  String _categoryFilter = 'All';
  final TextEditingController _searchController = TextEditingController();
  List<Transaction> _filteredTransactions = [];

  @override
  void initState() {
    super.initState();
    widget.dbHelper.getAllTransactions().then((transactions) {
      setState(() {
        _allTransactions = transactions;
        _filter();
      });
    });
    _searchController.addListener(_filter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter() {
    setState(() {
      _filteredTransactions = _allTransactions.where((tx) {
        if (tx.isRecurringSetup) return false; // Always hide setup entries
        final afterStartDate = _startDate == null || tx.date.isAfter(_startDate!.subtract(const Duration(days: 1)));
        final beforeEndDate = _endDate == null || tx.date.isBefore(_endDate!.add(const Duration(days: 1)));
        
        bool categoryMatch;
        if (_categoryFilter == 'All') {
          categoryMatch = true;
        } else if (_categoryFilter == 'Interest') {
          categoryMatch = ['Interest Charged', 'Interest Incurred'].contains(tx.category);
        } else {
          categoryMatch = tx.category == _categoryFilter;
        }

        final searchMatch = _searchController.text.isEmpty || tx.personName.toLowerCase().contains(_searchController.text.toLowerCase()) || tx.remarks.toLowerCase().contains(_searchController.text.toLowerCase());
        return afterStartDate && beforeEndDate && categoryMatch && searchMatch;
      }).toList();
    });
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2101),
      initialDateRange: _startDate != null && _endDate != null ? DateTimeRange(start: _startDate!, end: _endDate!) : null,
    );
    if (range != null) {
      setState(() { _startDate = range.start; _endDate = range.end; });
      _filter();
    }
  }

  Future<void> _exportToCsv() async {
    List<List<dynamic>> rows = [];
    rows.add(['Date', 'Person Name', 'Category', 'Amount', 'Mode', 'Remarks']);
    for (var tx in _filteredTransactions) {
      rows.add([
        DateFormat.yMMMd().format(tx.date),
        tx.personName,
        tx.category,
        tx.amount,
        tx.modeOfTransaction,
        tx.remarks
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/debtledger_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    final file = File(path);
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(path)], text: 'DebtLedger Report');
  }

  @override
  Widget build(BuildContext context) {
    double total = _filteredTransactions.fold(0.0, (sum, tx) {
      const creditCategories = ['You Lent', 'You Paid Back', 'Interest Charged'];
      if(creditCategories.contains(tx.category)){
        return sum + tx.amount;
      } else {
        return sum - tx.amount;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _filteredTransactions.isNotEmpty ? _exportToCsv : null,
            tooltip: 'Export as CSV',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterControls(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Card(
              color: Theme.of(context).primaryColor.withAlpha((255 * 0.1).round()),
              child: ListTile(
                title: const Text('Filtered Total', style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text(
                  NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(total),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).primaryColor),
                ),
              ),
            ),
          ),
          const Divider(),
          Expanded(child: _buildTransactionList()),
        ],
      ),
    );
  }

  Widget _buildFilterControls() {
    // New category list for filter chips
    final filterCategories = ['All', 'You Lent', 'You Borrowed', 'They Paid You', 'You Paid Back', 'Interest'];

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(labelText: 'Search Name/Remarks', prefixIcon: Icon(Icons.search)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _startDate != null && _endDate != null
                    ? '${DateFormat.yMMMd().format(_startDate!)} - ${DateFormat.yMMMd().format(_endDate!)}'
                    : 'Select Date Range',
              ),
              IconButton(icon: const Icon(Icons.calendar_today), onPressed: _pickDateRange),
            ],
          ),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: filterCategories.map((cat) {
              return FilterChip(
                label: Text(cat),
                selected: _categoryFilter == cat,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _categoryFilter = cat);
                    _filter();
                  }
                },
              );
            }).toList(),
          ),
          if (_startDate != null || _endDate != null || _categoryFilter != 'All' || _searchController.text.isNotEmpty)
            TextButton(onPressed: () { setState(() {
              _startDate = null; _endDate = null; _categoryFilter = 'All'; _searchController.clear();
            }); _filter(); }, child: const Text("Clear Filters"))
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_filteredTransactions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_alt_off_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text("No transactions match the filter.", style: TextStyle(fontSize: 18, color: Colors.grey)),
          ],
        )
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _filteredTransactions.length,
      itemBuilder: (context, index) {
        final tx = _filteredTransactions[index];
        const creditCategories = ['You Lent', 'You Paid Back', 'Interest Charged'];
        final color = creditCategories.contains(tx.category) ? Colors.green.shade700 : Colors.red.shade700;
        final formattedAmount = NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(tx.amount);
        return Card(
          child: ListTile(
            title: Text('${tx.personName} - $formattedAmount'),
            subtitle: Text('${DateFormat.yMMMd().format(tx.date)} - ${tx.modeOfTransaction}'),
            trailing: Text(tx.category, style: TextStyle(color: color)),
          ),
        );
      },
    );
  }
}


// --- Help Page ---
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).primaryColor);
    final subtitleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);
    final bulletPoint = Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(text: TextSpan(style: bodyStyle, children: [
            const TextSpan(text: '• ', style: TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: 'You Are Owed: The total amount of money others owe you.'),
          ])),
          const SizedBox(height: 4),
          RichText(text: TextSpan(style: bodyStyle, children: [
            const TextSpan(text: '• ', style: TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: 'You Owe: The total amount of money you owe to others.'),
          ])),
          const SizedBox(height: 4),
          RichText(text: TextSpan(style: bodyStyle, children: [
            const TextSpan(text: '• ', style: TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: 'Net Balance: The difference between the two, showing your overall financial position.'),
          ])),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('User Guide')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome to DebtLedger!', style: titleStyle),
            const SizedBox(height: 8),
            Text('This guide will help you understand all the features of the app to manage your debts and loans effectively.', style: bodyStyle),
            const Divider(height: 32),

            Text('1. The Dashboard', style: subtitleStyle),
            const SizedBox(height: 8),
            Text('The main screen gives you a quick overview of your finances:', style: bodyStyle),
            bulletPoint,
            Text('It also shows bar charts for a visual breakdown of your top debts and credits.', style: bodyStyle),
            const Divider(height: 32),

            Text('2. Core Features', style: subtitleStyle),
            const SizedBox(height: 8),
            _buildFeatureExplanation(
              context,
              title: 'Add Transaction',
              icon: Icons.add,
              content: 'For a single, one-time payment or loan. The form is smart: it auto-completes names and shows relevant categories based on your history with that person.',
            ),
            _buildFeatureExplanation(
              context,
              title: 'Add Recurring Payment',
              icon: Icons.repeat,
              content: 'To set up an automatic monthly EMI or interest payment. You set the amount and due day once, and the app automatically adds a transaction each month. This is perfect for loans with regular installments.',
            ),
            _buildFeatureExplanation(
              context,
              title: 'View Reports',
              icon: Icons.assessment,
              content: 'To see a complete list of all transactions. You can filter by date range, category, or search by name/remarks. You can also export this filtered view to a CSV file for your records.',
            ),
            const Divider(height: 32),
            
            Text('3. Understanding Categories', style: subtitleStyle),
            const SizedBox(height: 8),
            Text('The app uses a simple, action-based system to keep your ledger accurate:', style: bodyStyle),
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCategoryExplanation(context, 'You Lent:', 'Use when you give money to someone.'),
                  _buildCategoryExplanation(context, 'You Borrowed:', 'Use when you take money from someone.'),
                  _buildCategoryExplanation(context, 'They Paid You:', 'Use when someone pays back part or all of their debt to you.'),
                  _buildCategoryExplanation(context, 'You Paid Back:', 'Use when you pay back your debt to someone.'),
                  _buildCategoryExplanation(context, 'Add Interest:', 'To add a manual interest entry to a ledger.'),
                ],
              )
            ),
            const Divider(height: 32),

            Text('4. Managing Data & Security', style: subtitleStyle),
            const SizedBox(height: 8),
             _buildFeatureExplanation(
               context,
               title: 'App Lock & Privacy',
               icon: Icons.security,
               content: 'The app is protected by your device\'s biometrics (fingerprint/face) or a PIN. For extra privacy, the app\'s content is hidden from your phone\'s "recent apps" list.',
             ),
            _buildFeatureExplanation(
              context,
              title: 'Manual Backup & Restore',
              icon: Icons.backup,
              content: 'In Settings (⚙️), you can create an encrypted backup file. You must provide a password. Use the "Restore" option with this file and password to get your data back on a new device. Keep this file safe!',
            ),
             _buildFeatureExplanation(
               context,
               title: 'Automatic Weekly Backup',
               icon: Icons.update,
               content: 'The app automatically creates a local, encrypted backup every 7 days using your PIN as the password. It only keeps the single latest backup file. This is a safety net in case of accidental data loss on your device.',
             ),
            _buildFeatureExplanation(
              context,
              title: 'Import from CSV',
              icon: Icons.upload_file,
              content: 'In Settings (⚙️), you can bulk-import transactions from a CSV file. Download the template, fill it with your data, and the app will validate and import it for you.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureExplanation(BuildContext context, {required String title, required IconData icon, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).primaryColor, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(content, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCategoryExplanation(BuildContext context, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          children: [
            TextSpan(text: '• $title ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: description),
          ]
        )
      ),
    );
  }
}

// --- NEW: IMPORT CSV FEATURE ---

// Helper class to hold validated row data
class ValidatedRow {
  final int rowNumber;
  final Transaction? transaction;
  final String? error;

  ValidatedRow({required this.rowNumber, this.transaction, this.error});
}

// The main import screen
class ImportCsvPage extends StatefulWidget {
  const ImportCsvPage({super.key});

  @override
  State<ImportCsvPage> createState() => _ImportCsvPageState();
}

class _ImportCsvPageState extends State<ImportCsvPage> {
  bool _isLoading = false;

  Future<void> _downloadTemplate() async {
    const csvTemplate = 
      'date,personName,amount,category,modeOfTransaction,remarks\n'
      '"_instruction","Enter date in YYYY-MM-DD format (e.g., 2025-10-28)","Do not use commas or currency symbols","Valid categories: You Lent, You Borrowed, They Paid You, You Paid Back","Valid modes: Cash, Bank Transfer, UPI, Other","Optional notes"\n'
      '"_example","2025-01-15","John Doe","5000","You Lent","UPI","For the weekend trip"\n'
      '"_example","2025-01-16","Jane Smith","1250.50","You Borrowed","Cash","Lunch money"';

    try {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/DebtLedger_Import_Template.csv';
      final file = File(path);
      await file.writeAsString(csvTemplate);
      await Share.shareXFiles([XFile(path)], text: 'DebtLedger CSV Import Template');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating template: $e')));
      }
    }
  }
  
  // --- REVISED AND SIMPLIFIED FILE PICKING LOGIC ---
  Future<void> _pickAndReadFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isLoading = true);

    try {
      // The file_picker package itself handles showing the system's file selection UI.
      // On modern Android, this doesn't require a separate permission request beforehand.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.single.path == null) {
        if (mounted) {
           messenger.showSnackBar(const SnackBar(content: Text("No file selected.")));
           setState(() => _isLoading = false);
        }
        return;
      }

      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final validatedData = _validateCsvData(content);

      if (!mounted) return;
      final resultFromPreview = await navigator.push<bool>(MaterialPageRoute(builder: (context) => 
        PreviewImportPage(validatedRows: validatedData)
      ));
      
      // If import was successful on the preview page, pop this page too
      if (resultFromPreview == true && mounted) {
        navigator.pop(true);
      }
    } on PlatformException catch (e) {
      // This can happen if the user denies access through the native picker UI.
      messenger.showSnackBar(SnackBar(content: Text("File access error: ${e.message}")));
    } catch(e) {
      messenger.showSnackBar(SnackBar(content: Text("Error processing file: $e")));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  List<ValidatedRow> _validateCsvData(String csvData) {
    final List<List<dynamic>> rows = const CsvToListConverter(shouldParseNumbers: false).convert(csvData);
    final List<ValidatedRow> validatedRows = [];
    final validCategories = ['You Lent', 'You Borrowed', 'They Paid You', 'You Paid Back'];
    final validModes = ['Cash', 'Bank Transfer', 'UPI', 'Other'];

    for (int i = 0; i < rows.length; i++) {
      // Skip header or instruction rows
      if (i == 0 || (rows[i].isNotEmpty && rows[i][0].toString().startsWith('_'))) continue;

      final row = rows[i];
      if (row.length < 4) {
        validatedRows.add(ValidatedRow(rowNumber: i + 1, error: 'Row does not have enough columns (expected at least 4).'));
        continue;
      }
      
      final dateStr = row[0].toString();
      final personName = row[1].toString();
      final amountStr = row[2].toString();
      final category = row[3].toString();
      final mode = row.length > 4 ? row[4].toString() : 'Other';
      final remarks = row.length > 5 ? row[5].toString() : '';

      final date = DateTime.tryParse(dateStr);
      if (date == null) {
        validatedRows.add(ValidatedRow(rowNumber: i + 1, error: 'Invalid date format. Expected YYYY-MM-DD.'));
        continue;
      }

      if (personName.trim().isEmpty) {
        validatedRows.add(ValidatedRow(rowNumber: i + 1, error: 'Person\'s name cannot be empty.'));
        continue;
      }
      
      final amount = double.tryParse(amountStr);
      if (amount == null || amount <= 0) {
        validatedRows.add(ValidatedRow(rowNumber: i + 1, error: 'Invalid amount. Must be a positive number.'));
        continue;
      }

      if (!validCategories.contains(category)) {
        validatedRows.add(ValidatedRow(rowNumber: i + 1, error: 'Invalid category: "$category".'));
        continue;
      }
      
      if (!validModes.contains(mode)) {
        validatedRows.add(ValidatedRow(rowNumber: i + 1, error: 'Invalid mode: "$mode".'));
        continue;
      }

      validatedRows.add(ValidatedRow(
        rowNumber: i + 1,
        transaction: Transaction(
          date: date,
          personName: personName.trim(),
          amount: amount,
          category: category,
          modeOfTransaction: mode,
          remarks: remarks.trim(),
        )
      ));
    }
    return validatedRows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from CSV')),
      body: _isLoading 
      ? const Center(child: CircularProgressIndicator())
      : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Instructions', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('1. Download the CSV template file.\n2. Open it in a spreadsheet app (like Excel or Google Sheets).\n3. Fill in your transaction data, following the format rules.\n4. Save the file and select it below to import.'),
            const Divider(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download Template CSV'),
              onPressed: _downloadTemplate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade700
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload),
              label: const Text('Select CSV File to Import'),
              onPressed: _pickAndReadFile,
            ),
          ],
        ),
      ),
    );
  }
}

// The preview screen before final import
class PreviewImportPage extends StatelessWidget {
  final List<ValidatedRow> validatedRows;
  const PreviewImportPage({super.key, required this.validatedRows});

  @override
  Widget build(BuildContext context) {
    final validTransactions = validatedRows.where((r) => r.transaction != null).map((r) => r.transaction!).toList();
    final invalidRows = validatedRows.where((r) => r.error != null).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Preview Import')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              color: Theme.of(context).primaryColor.withAlpha((255 * 0.1).round()),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text('Import Summary', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('${validTransactions.length} valid transactions found.', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    Text('${invalidRows.length} rows have errors and will be skipped.', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )
          ),
          if (invalidRows.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('Errors Found', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              flex: 1,
              child: ListView.builder(
                itemCount: invalidRows.length,
                itemBuilder: (context, index) {
                  final row = invalidRows[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    color: Colors.red.shade50,
                    child: ListTile(
                      title: Text('Row ${row.rowNumber}: Error'),
                      subtitle: Text(row.error!),
                      dense: true,
                    ),
                  );
                },
              ),
            ),
          ],
          if (validTransactions.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text('Transactions to be Imported', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              flex: 2,
              child: ListView.builder(
                itemCount: validTransactions.length,
                itemBuilder: (context, index) {
                  final tx = validTransactions[index];
                  return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text('${tx.personName} - ${NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(tx.amount)}'),
                        subtitle: Text(tx.category),
                        trailing: Text(DateFormat.yMMMd().format(tx.date)),
                      ),
                  );
                },
              ),
            ),
          ]
        ],
      ),
      floatingActionButton: validTransactions.isNotEmpty ? FloatingActionButton.extended(
        onPressed: () async {
          final db = DatabaseHelper();
          for (final tx in validTransactions) {
            await db.addTransaction(tx);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully imported ${validTransactions.length} transactions.')));
            Navigator.of(context).pop(true); // Return true to signal success
          }
        },
        label: Text('Confirm & Import ${validTransactions.length}'),
        icon: const Icon(Icons.check),
      ) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

