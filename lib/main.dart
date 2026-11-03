import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

void main() {
  runApp(const ApplicationLivre());
}

class ApplicationLivre extends StatelessWidget {
  const ApplicationLivre({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  Widget build(BuildContext context) {
    const forest = Color(0xFF304436);

    return MaterialApp(
      title: 'Bibliothèque',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: forest,
          surface: const Color(0xFFFAF8F3),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF8F3),
        useMaterial3: true,
        fontFamily: 'Georgia',
      ),
      home: HomePage(apiClient: apiClient),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  late final ApiClient _api;
  bool _ownsApi = false;
  String _searchText = '';
  int _selectedTab = 0;
  List<Book> _libraryBooks = [];
  bool _isLoadingLibrary = false;
  String? _libraryError;
  Map<String, dynamic>? _currentUser;
  bool _isRestoringSession = true;
  List<Book>? _catalogueBooks;
  bool _isLoadingCatalogue = false;
  String? _catalogueError;
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    _api = widget.apiClient ?? ApiClient();
    _ownsApi = widget.apiClient == null;
    _restoreSession();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestoringSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_currentUser == null) {
      return _AuthenticationPage(
        api: _api,
        initialRegister: true,
        onAuthenticated: _acceptAuthenticatedUser,
      );
    }

    final isAdmin = _currentUser?['role'] == 'admin';
    final isAuthor = _currentUser?['role'] == 'author';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _selectedTab == 0
                ? _buildDiscoverPage()
                : _selectedTab == 1
                ? isAdmin
                      ? _buildAdminEntryPage()
                      : isAuthor
                      ? _buildAuthorEntryPage()
                      : _buildLibraryPage()
                : _buildProfilePage(),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Découvrir',
          ),
          NavigationDestination(
            icon: Icon(
              isAdmin
                  ? Icons.admin_panel_settings_outlined
                  : isAuthor
                  ? Icons.upload_file_outlined
                  : Icons.menu_book_outlined,
            ),
            selectedIcon: Icon(
              isAdmin
                  ? Icons.admin_panel_settings
                  : isAuthor
                  ? Icons.upload_file
                  : Icons.menu_book,
            ),
            label: isAdmin
                ? 'Administration'
                : isAuthor
                ? 'Mes livres'
                : 'Ma bibliothèque',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverPage() {
    final books = (_catalogueBooks ?? <Book>[])
        .where(
          (book) =>
              book.title.toLowerCase().contains(_searchText.toLowerCase()) ||
              book.author.toLowerCase().contains(_searchText.toLowerCase()),
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 22),
          const Text(
            'Votre prochaine lecture vous attend.',
            style: TextStyle(
              fontSize: 26,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: Color(0xFF28372D),
            ),
          ),
          const SizedBox(height: 18),
          _buildSearchField(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isLoadingCatalogue ? null : _loadCatalogue,
            icon: _isLoadingCatalogue
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
            label: Text(
              _catalogueBooks == null
                  ? 'Charger le catalogue en ligne'
                  : 'Actualiser le catalogue en ligne',
            ),
          ),
          if (_catalogueError != null) ...[
            const SizedBox(height: 8),
            Text(_catalogueError!, style: const TextStyle(color: Colors.red)),
          ],
          if (_catalogueBooks != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Catalogue chargé depuis le serveur.',
              style: TextStyle(color: Color(0xFF647660), fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          _buildLibraryBanner(),
          const SizedBox(height: 28),
          _buildSectionTitle('Livres disponibles', 'En ligne'),
          const SizedBox(height: 14),
          if (_isLoadingCatalogue && _catalogueBooks == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (books.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Aucun livre en ligne ne correspond à la recherche.'),
            )
          else
            SizedBox(
              height: 245,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: books.length,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) => _BookCard(
                  book: books[index],
                  onTap: () => _showBookPreview(books[index]),
                ),
              ),
            ),
          const SizedBox(height: 22),
          const Text(
            'Après confirmation du paiement, le fichier original est disponible dans votre bibliothèque.',
            style: TextStyle(color: Color(0xFF77766F), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE9EDE6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.auto_stories, color: Color(0xFF304436)),
        ),
        const SizedBox(width: 11),
        const Text(
          'Ma lecture',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF28372D),
          ),
        ),
        const Spacer(),
        if (_currentUser == null)
          TextButton(
            onPressed: _openAuthentication,
            child: const Text('Connexion'),
          )
        else
          Tooltip(
            message: _currentUser?['displayName'] as String? ?? 'Mon compte',
            child: const Icon(Icons.verified_user_outlined),
          ),
        IconButton(
          tooltip: 'Ma bibliothèque',
          onPressed: () => setState(() => _selectedTab = 1),
          icon: const Icon(Icons.bookmark_border),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchText = value),
      decoration: InputDecoration(
        hintText: 'Rechercher un livre ou un auteur',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE8E5DD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE8E5DD)),
        ),
      ),
    );
  }

  Widget _buildLibraryBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 176,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('4.jpg', fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF17251D).withValues(alpha: 0.88),
                    const Color(0xFF17251D).withValues(alpha: 0.18),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'La lecture vous accompagne.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Retrouvez vos livres au même endroit.',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _selectedTab = 1),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Voir ma bibliothèque'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String action) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF28372D),
          ),
        ),
        const Spacer(),
        Text(
          action,
          style: const TextStyle(
            color: Color(0xFF647660),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryPage() {
    if (_isLoadingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_libraryError != null) {
      return _EmptyPage(
        icon: Icons.error_outline,
        title: 'Bibliothèque indisponible',
        message: _libraryError!,
        buttonLabel: 'Réessayer',
        onPressed: _loadLibrary,
      );
    }

    if (_libraryBooks.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          const Text(
            'Votre bibliothèque',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              color: Color(0xFF28372D),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Retrouvez ici les livres que vous avez achetés.',
            style: TextStyle(color: Color(0xFF696B64), height: 1.4),
          ),
          const SizedBox(height: 18),
          for (final book in _libraryBooks) ...[
            Card(
              color: Colors.white,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                leading: _BookCover(book: book, width: 44, height: 58),
                title: Text(
                  book.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(book.author),
                onTap: () => _showBookPreview(book, alreadyPaid: true),
                trailing: IconButton(
                  tooltip: 'Télécharger ${book.title}',
                  onPressed: () => _showBookPreview(book, alreadyPaid: true),
                  icon: const Icon(Icons.download_outlined),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return _EmptyPage(
      icon: Icons.menu_book_outlined,
      title: 'Votre bibliothèque',
      message: 'Les livres achetés apparaîtront ici.',
      buttonLabel: 'Découvrir les livres',
      onPressed: () => setState(() => _selectedTab = 0),
    );
  }

  Widget _buildProfilePage() {
    final user = _currentUser;
    if (user == null) {
      return _EmptyPage(
        icon: Icons.person_outline,
        title: 'Votre profil',
        message:
            _sessionError ??
            'Connectez-vous pour accéder à votre compte, déposer des livres '
                'ou gérer votre espace.',
        buttonLabel: 'Créer un compte ou se connecter',
        onPressed: _openAuthentication,
      );
    }

    final role = user['role'] as String? ?? 'reader';
    final actions = <Widget>[];
    if (role == 'author') {
      actions.add(
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('Mes livres et dépôts'),
          onTap: () => setState(() => _selectedTab = 1),
        ),
      );
    }
    if (role == 'admin') {
      actions.add(
        ListTile(
          leading: const Icon(Icons.admin_panel_settings),
          title: const Text('Administration et modération'),
          onTap: () => setState(() => _selectedTab = 1),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.account_circle_outlined, size: 60),
        const SizedBox(height: 12),
        Text(
          user['displayName'] as String? ?? 'Mon profil',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        Text(user['email'] as String? ?? '', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Center(child: Chip(label: Text(_roleLabel(role)))),
        ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text('Modifier mon e-mail ou mon mot de passe'),
          onTap: _editProfile,
        ),
        if (_sessionError != null)
          ListTile(
            leading: const Icon(Icons.warning_amber, color: Colors.orange),
            title: Text(_sessionError!),
          ),
        ...actions,
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('Se déconnecter'),
        ),
      ],
    );
  }

  Widget _buildAuthorEntryPage() {
    return _AuthorPage(api: _api);
  }

  Widget _buildAdminEntryPage() {
    return _AdminPage(api: _api);
  }

  Future<void> _restoreSession() async {
    try {
      if (await _api.readToken() == null) {
        if (mounted) setState(() => _isRestoringSession = false);
        await _loadCatalogue();
        return;
      }
      final result = await _api.currentUser();
      if (!mounted) return;
      setState(() {
        final user = Map<String, dynamic>.from(result['user'] as Map);
        _currentUser = user;
        _selectedTab = user['role'] == 'admin' ? 1 : 0;
        _sessionError = null;
        _isRestoringSession = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) await _api.logout();
      setState(() {
        _sessionError = error.message;
        _isRestoringSession = false;
      });
      await _loadCatalogue();
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sessionError = 'Session indisponible : $error';
        _isRestoringSession = false;
      });
      await _loadCatalogue();
      return;
    }
    await _loadCatalogue();
    if (_currentUser?['role'] != 'admin') await _loadLibrary();
  }

  Future<void> _acceptAuthenticatedUser(Map<String, dynamic> user) async {
    if (!mounted) return;
    final isAdmin = user['role'] == 'admin';
    setState(() {
      _currentUser = user;
      _sessionError = null;
      _selectedTab = isAdmin ? 1 : 0;
    });
    await _loadCatalogue();
    if (!isAdmin) await _loadLibrary();
  }

  Future<void> _openAuthentication() async {
    final user = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) =>
            _AuthenticationPage(api: _api, initialRegister: false),
      ),
    );
    if (!mounted || user == null) return;
    await _acceptAuthenticatedUser(user);
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    setState(() {
      _currentUser = null;
      _catalogueBooks = null;
      _libraryBooks = [];
      _selectedTab = 0;
    });
  }

  String _roleLabel(String role) => switch (role) {
    'author' => 'Auteur',
    'admin' => 'Administrateur',
    _ => 'Lecteur',
  };

  Future<void> _loadCatalogue() async {
    setState(() {
      _isLoadingCatalogue = true;
      _catalogueError = null;
    });
    try {
      final result = await _api.books(search: _searchText);
      if (!mounted) return;
      setState(() {
        _catalogueBooks = result.map(Book.fromApi).toList();
        _isLoadingCatalogue = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _catalogueError = error.message;
        _isLoadingCatalogue = false;
      });
    }
  }

  Future<void> _showPaymentSuccess(Book book) async {
    if (!mounted) return;
    setState(() => _selectedTab = 0);
    await _loadLibrary();
    if (!mounted) return;

    final openBook = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Paiement réussi'),
        content: Text(
          'Votre achat de « ${book.title} » est confirmé. '
          'Appuyez sur OK pour accéder à votre livre.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (mounted && openBook == true) {
      _showBookPreview(book, alreadyPaid: true);
    }
  }

  void _showBookPreview(Book book, {bool alreadyPaid = false}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        child: _BookPreviewSheet(
          api: _api,
          book: book,
          alreadyPaid: alreadyPaid,
          onPaymentSucceeded: _showPaymentSuccess,
        ),
      ),
    );
  }

  Future<void> _loadLibrary() async {
    if (_currentUser == null || _currentUser?['role'] == 'admin') {
      if (mounted) {
        setState(() {
          _libraryBooks = [];
          _isLoadingLibrary = false;
          _libraryError = null;
        });
      }
      return;
    }
    setState(() {
      _isLoadingLibrary = true;
      _libraryError = null;
    });

    try {
      final result = await _api.purchasedBooks();
      if (!mounted) return;
      setState(() {
        _libraryBooks = result.map(Book.fromApi).toList();
        _isLoadingLibrary = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _libraryError = error.message;
        _isLoadingLibrary = false;
      });
    }
  }

  Future<void> _editProfile() async {
    final user = _currentUser;
    if (user == null) return;
    final updatedUser = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) =>
          _EditProfileSheet(api: _api, email: user['email'] as String? ?? ''),
    );
    if (!mounted || updatedUser == null) return;
    setState(() => _currentUser = updatedUser);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Votre profil a été mis à jour.')),
    );
  }
}

class _BookPreviewSheet extends StatefulWidget {
  const _BookPreviewSheet({
    required this.api,
    required this.book,
    required this.alreadyPaid,
    required this.onPaymentSucceeded,
  });

  final ApiClient api;
  final Book book;
  final bool alreadyPaid;
  final Future<void> Function(Book book) onPaymentSucceeded;

  @override
  State<_BookPreviewSheet> createState() => _BookPreviewSheetState();
}

class _BookPreviewSheetState extends State<_BookPreviewSheet>
    with WidgetsBindingObserver {
  int? _orderId;
  String? _paymentUrl;
  String? _error;
  late bool _isPaid;
  bool _isBusy = false;
  bool _isCheckingPayment = false;
  bool _paymentSuccessHandled = false;
  Timer? _paymentPollTimer;

  @override
  void initState() {
    super.initState();
    _isPaid = widget.alreadyPaid;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _orderId != null) {
      unawaited(_verifyPayment());
    }
  }

  Future<void> _payOrVerify() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      if (_isPaid) {
        await _downloadPurchasedBook();
      } else if (_orderId != null) {
        final paid = await _verifyPayment();
        if (!paid && mounted && _error == null) {
          setState(() {
            _error =
                'Paiement non confirmé. Terminez le paiement, puis réessayez.';
          });
        }
      } else {
        final result = await widget.api.createPaymentCheckout(widget.book.id!);
        if (result['alreadyPaid'] == true) {
          await _completePayment();
        } else {
          final orderId = result['orderId'];
          final paymentUrl = result['paymentUrl'];
          if (orderId is! num || paymentUrl is! String) {
            throw const ApiException(
              'Le serveur n’a pas fourni le lien de paiement.',
            );
          }
          final uri = Uri.tryParse(paymentUrl);
          if (uri == null || uri.scheme != 'https') {
            throw const ApiException(
              'Le lien de paiement FedaPay est invalide.',
            );
          }
          setState(() {
            _orderId = orderId.toInt();
            _paymentUrl = paymentUrl;
          });
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!launched) {
            setState(() {
              _error = 'Impossible d’ouvrir la page de paiement. Réessayez.';
            });
          } else {
            _startPaymentPolling();
          }
        }
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Opération impossible : $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _verifyPayment() async {
    final orderId = _orderId;
    if (orderId == null || _isCheckingPayment || _paymentSuccessHandled) {
      return false;
    }

    _isCheckingPayment = true;
    try {
      final result = await widget.api.verifyPayment(orderId);
      if (result['paid'] == true) {
        await _completePayment();
        return true;
      }
      if (result['paid'] != false) {
        throw const ApiException(
          'Le serveur n’a pas retourné un statut de paiement valide.',
        );
      }
      return false;
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Vérification du paiement impossible : $error');
      }
      return false;
    } finally {
      _isCheckingPayment = false;
    }
  }

  void _startPaymentPolling() {
    _paymentPollTimer?.cancel();
    final expiresAt = DateTime.now().add(const Duration(minutes: 2));
    _paymentPollTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || DateTime.now().isAfter(expiresAt)) {
        timer.cancel();
        if (mounted && !_paymentSuccessHandled) {
          setState(() {
            _error =
                'Le paiement est toujours en attente. Revenez ici et '
                'appuyez sur « Vérifier mon paiement ».';
          });
        }
        return;
      }
      unawaited(_verifyPayment());
    });
  }

  Future<void> _completePayment() async {
    if (_paymentSuccessHandled || !mounted) return;
    _paymentSuccessHandled = true;
    _paymentPollTimer?.cancel();
    setState(() => _isPaid = true);
    Navigator.of(context).pop();
    await widget.onPaymentSucceeded(widget.book);
  }

  Future<void> _reopenPayment() async {
    final paymentUrl = _paymentUrl;
    if (paymentUrl == null) return;
    final launched = await launchUrl(
      Uri.parse(paymentUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      setState(() => _error = 'Impossible d’ouvrir la page de paiement.');
    }
  }

  Future<void> _downloadPurchasedBook() async {
    final response = await widget.api.downloadPurchasedFile(widget.book.id!);
    final fileName = '${widget.book.title}.${widget.book.fileType ?? 'pdf'}'
        .replaceAll(RegExp(r'["\\/\r\n]'), '_');
    await FilePicker.saveFile(
      fileName: fileName,
      bytes: response.bodyBytes,
      mimeType: widget.book.fileType == 'docx'
          ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
          : 'application/pdf',
      dialogTitle: 'Enregistrer le livre acheté',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Téléchargement du livre prêt.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            book.title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('Par ${book.author}'),
          const SizedBox(height: 18),
          const Text(
            'Après confirmation du paiement, vous pourrez télécharger le fichier original.',
          ),
          if (book.id != null) ...[
            const SizedBox(height: 12),
            Text(
              'Prix : ${book.price} ${book.currency}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Paiement FedaPay en mode sandbox : aucun débit réel. Les reversements aux auteurs ne sont pas automatiques.',
              style: TextStyle(color: Color(0xFF69758A), fontSize: 12),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _payOrVerify,
              icon: _isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_isPaid ? Icons.download : Icons.payment),
              label: Text(
                _isBusy
                    ? 'Vérification...'
                    : _isPaid
                    ? 'Télécharger le livre'
                    : _orderId == null
                    ? 'Payer avec FedaPay'
                    : 'Vérifier mon paiement',
              ),
            ),
          ),
          if (_orderId != null && !_isPaid) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _reopenPayment,
                child: const Text('Rouvrir la page de paiement'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthenticationPage extends StatefulWidget {
  const _AuthenticationPage({
    required this.api,
    required this.initialRegister,
    this.onAuthenticated,
  });

  final ApiClient api;
  final bool initialRegister;
  final ValueChanged<Map<String, dynamic>>? onAuthenticated;

  @override
  State<_AuthenticationPage> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends State<_AuthenticationPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = false;
  bool _isAuthor = false;
  bool _isSubmitting = false;
  bool _showPassword = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _isRegistering = widget.initialRegister;
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
      _notice = null;
    });

    try {
      if (_isRegistering) {
        final registration = await widget.api.register(
          email: _email.text.trim(),
          displayName: _name.text.trim(),
          password: _password.text,
          accountType: _isAuthor ? 'author' : 'reader',
        );
        if (_isAuthor) {
          if (!mounted) return;
          setState(() {
            _isSubmitting = false;
            _error =
                registration['message'] as String? ??
                'Votre demande attend la validation de l’administrateur.';
            _isRegistering = false;
          });
          return;
        }
      }

      final result = await widget.api.login(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      final user = Map<String, dynamic>.from(result['user'] as Map);
      if (widget.onAuthenticated case final onAuthenticated?) {
        onAuthenticated(user);
      } else {
        Navigator.of(context).pop(user);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _notice = null;
        _isSubmitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Une erreur est survenue : $error';
        _notice = null;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF3563F6);
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: const Color(0xFFF4F8FC),
        colorScheme: theme.colorScheme.copyWith(primary: accent),
        textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F8FC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          prefixIconColor: const Color(0xFF8793A7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: accent, width: 1.4),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: theme.colorScheme.error.withValues(alpha: 0.6),
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: theme.colorScheme.error),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(child: Image.asset('3.jpg', fit: BoxFit.cover)),
            const Positioned.fill(child: ColoredBox(color: Color(0x330F2238))),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 28,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(26, 30, 26, 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF233B68)
                                  .withValues(alpha: 0.08),
                              blurRadius: 32,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF3FF),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(
                                    Icons.auto_stories_rounded,
                                    color: accent,
                                    size: 29,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _isRegistering
                                    ? 'Créer un compte'
                                    : 'Connexion',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF315EF5),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isRegistering
                                    ? 'Rejoignez Ma lecture et découvrez votre prochain livre.'
                                    : 'Connectez-vous pour retrouver votre bibliothèque.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF778397),
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 26),
                              if (_isRegistering) ...[
                                TextFormField(
                                  controller: _name,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Nom affiché',
                                    prefixIcon: Icon(
                                      Icons.person_outline_rounded,
                                    ),
                                  ),
                                  validator: (value) =>
                                      (value?.trim().length ?? 0) < 2
                                      ? 'Entrez au moins deux caractères.'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<bool>(
                                  initialValue: _isAuthor,
                                  decoration: const InputDecoration(
                                    labelText: 'Type de compte',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: false,
                                      child: Text('Lecteur'),
                                    ),
                                    DropdownMenuItem(
                                      value: true,
                                      child: Text('Auteur'),
                                    ),
                                  ],
                                  onChanged: _isSubmitting
                                      ? null
                                      : (value) => setState(
                                          () => _isAuthor = value ?? false,
                                        ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Adresse e-mail',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  return email.contains('@')
                                      ? null
                                      : 'Adresse e-mail invalide.';
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _password,
                                obscureText: !_showPassword,
                                autofillHints: [
                                  _isRegistering
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Mot de passe',
                                  helperText: _isRegistering
                                      ? '8 caractères minimum.'
                                      : null,
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: _showPassword
                                        ? 'Masquer le mot de passe'
                                        : 'Afficher le mot de passe',
                                    onPressed: () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (!_isRegistering &&
                                      (value?.isEmpty ?? true)) {
                                    return 'Entrez votre mot de passe.';
                                  }
                                  if (_isRegistering &&
                                      (value?.length ?? 0) < 8) {
                                    return 'Utilisez au moins 8 caractères.';
                                  }
                                  return null;
                                },
                              ),
                              if (!_isRegistering)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _isSubmitting
                                        ? null
                                        : _requestPasswordReset,
                                    child: const Text('Mot de passe oublié ?'),
                                  ),
                                ),
                              if (_notice != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _notice!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _isAuthor && !_isRegistering
                                        ? Colors.green.shade800
                                        : Theme.of(context).colorScheme.error,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 52,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                  ),
                                  onPressed: _isSubmitting ? null : _submit,
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          _isRegistering
                                              ? 'Créer mon compte'
                                              : 'Se connecter',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    _isRegistering
                                        ? 'Vous avez déjà un compte ? '
                                        : 'Pas encore de compte ? ',
                                    style: const TextStyle(
                                      color: Color(0xFF69758A),
                                      fontSize: 13,
                                    ),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: accent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: _isSubmitting
                                        ? null
                                        : () => setState(() {
                                            _isRegistering = !_isRegistering;
                                            _error = null;
                                          }),
                                    child: Text(
                                      _isRegistering
                                          ? 'Se connecter'
                                          : 'S’inscrire',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestPasswordReset() async {
    var emailValue = _email.text.trim();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Réinitialiser le mot de passe'),
        content: TextFormField(
          initialValue: emailValue,
          keyboardType: TextInputType.emailAddress,
          onChanged: (value) => emailValue = value.trim(),
          decoration: const InputDecoration(labelText: 'Adresse e-mail'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, emailValue),
            child: const Text('Envoyer le lien'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await widget.api.requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _email.text = email;
        _notice =
            result['message'] as String? ??
            'Si cette adresse possède un compte, un lien a été envoyé.';
        _isSubmitting = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _isSubmitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Envoi impossible : $error';
        _isSubmitting = false;
      });
    }
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.api, required this.email});

  final ApiClient api;
  final String email;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.email);
  }

  @override
  void dispose() {
    _email.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    final newPassword = _newPassword.text;
    if (email == widget.email && newPassword.isEmpty) {
      setState(() => _error = 'Modifiez l’e-mail ou le mot de passe.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final result = await widget.api.updateProfile(
        currentPassword: _currentPassword.text,
        email: email == widget.email ? null : email,
        newPassword: newPassword.isEmpty ? null : newPassword,
      );
      if (mounted) {
        Navigator.of(context)
            .pop(Map<String, dynamic>.from(result['user'] as Map));
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _isSaving = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Modification impossible : $error';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Modifier mon profil',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Nouvel e-mail'),
                validator: (value) => (value ?? '').contains('@')
                    ? null
                    : 'Adresse e-mail invalide.',
              ),
              TextFormField(
                controller: _currentPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe actuel (obligatoire)',
                ),
                validator: (value) => (value?.isEmpty ?? true)
                    ? 'Saisissez votre mot de passe actuel.'
                    : null,
              ),
              TextFormField(
                controller: _newPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe (facultatif)',
                ),
                validator: (value) =>
                    value != null && value.isNotEmpty && value.length < 8
                    ? 'Utilisez au moins 8 caractères.'
                    : null,
              ),
              TextFormField(
                controller: _confirmPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmer le nouveau mot de passe',
                ),
                validator: (value) =>
                    _newPassword.text.isNotEmpty && value != _newPassword.text
                    ? 'Les mots de passe ne correspondent pas.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const CircularProgressIndicator()
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorPage extends StatefulWidget {
  const _AuthorPage({required this.api});

  final ApiClient api;

  @override
  State<_AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<_AuthorPage> {
  List<Map<String, dynamic>> _books = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final books = await widget.api.authorBooks();
      if (!mounted) return;
      setState(() {
        _books = books;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _openUpload() async {
    final uploaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _UploadBookSheet(api: widget.api),
    );
    if (uploaded == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Mes livres',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                onPressed: _openUpload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Déposer'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'PDF ou DOCX, 25 Mo maximum. Le livre est publié dès son dépôt.',
          ),
        ),
        if (_error != null)
          ListTile(
            leading: const Icon(Icons.error_outline, color: Colors.red),
            title: Text(_error!),
            trailing: IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _books.isEmpty
              ? const Center(
                  child: Text('Vous n’avez pas encore déposé de livre.'),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _books.length,
                    itemBuilder: (context, index) {
                      final book = _books[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.menu_book),
                          title: Text(book['title'] as String? ?? 'Livre'),
                          subtitle: Text(
                            '${book['price_amount'] ?? ''} ${book['currency'] ?? ''}'
                            ' · ${book['file_type'] ?? ''}',
                          ),
                          trailing: Chip(
                            label: Text(
                              _statusLabel(book['status'] as String?),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  String _statusLabel(String? status) => switch (status) {
    'approved' => 'Publié',
    'rejected' => 'Refusé',
    _ => 'En attente',
  };
}

class _UploadBookSheet extends StatefulWidget {
  const _UploadBookSheet({required this.api});

  final ApiClient api;

  @override
  State<_UploadBookSheet> createState() => _UploadBookSheetState();
}

class _UploadBookSheetState extends State<_UploadBookSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  PlatformFile? _file;
  PlatformFile? _coverImage;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx'],
    );
    if (!mounted || result.isEmpty) return;
    setState(() {
      _file = result.single;
      _error = null;
    });
  }

  Future<void> _chooseCover() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (!mounted || result.isEmpty) return;
    setState(() {
      _coverImage = result.single;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_file == null) {
      setState(() => _error = 'Sélectionnez un fichier PDF ou DOCX.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.api.uploadBook(
        title: _title.text.trim(),
        description: _description.text.trim(),
        price: _price.text.trim().replaceAll(',', '.'),
        currency: 'XOF',
        file: _file!,
        coverImage: _coverImage,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _isSubmitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Envoi impossible : $error';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Déposer un livre',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'Saisissez un titre.'
                    : null,
              ),
              TextFormField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (value) => (value?.trim().length ?? 0) < 10
                    ? 'La description doit contenir au moins 10 caractères.'
                    : null,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Prix en XOF',
                      ),
                      validator: (value) {
                        final amount = double.tryParse(
                          (value ?? '').replaceAll(',', '.'),
                        );
                        return amount == null ||
                                amount < 1 ||
                                amount != amount.roundToDouble()
                            ? 'Saisissez un prix entier en XOF (minimum 1).'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'XOF',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _chooseFile,
                icon: const Icon(Icons.attach_file),
                label: Text(_file?.name ?? 'Choisir un fichier PDF ou DOCX'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _chooseCover,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  _coverImage?.name ?? 'Choisir une couverture (facultatif)',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Publier mon livre'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminPage extends StatefulWidget {
  const _AdminPage({required this.api});

  final ApiClient api;

  @override
  State<_AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<_AdminPage> {
  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _commission;
  Map<String, dynamic>? _paymentProvider;
  final _commissionController = TextEditingController();
  bool _isLoading = true;
  bool _isSavingCommission = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _commissionController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final books = await widget.api.adminBooks();
      final users = await widget.api.adminUsers(status: 'pending');
      final commission = await widget.api.commission();
      final paymentProvider = await widget.api.paymentProvider();
      if (!mounted) return;
      setState(() {
        _books = books;
        _users = users;
        _commission = commission;
        _commissionController.text = commission['percent']?.toString() ?? '';
        _paymentProvider = paymentProvider;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeBook(Map<String, dynamic> book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer ce livre ?'),
        content: Text(
          '« ${book['title'] ?? 'Livre'} » ne sera plus visible dans le catalogue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.removeAdminBook((book['id'] as num).toInt());
      if (mounted) await _refresh();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _activateUser(Map<String, dynamic> user) async {
    try {
      await widget.api.setUserStatus(
        userId: (user['id'] as num).toInt(),
        status: 'active',
      );
      if (mounted) await _refresh();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _downloadBook(Map<String, dynamic> book) async {
    try {
      final response = await widget.api.downloadAdminFile(
        (book['id'] as num).toInt(),
      );
      final fileName = (book['original_file_name'] as String? ?? 'livre')
          .replaceAll(RegExp(r'["\\/\r\n]'), '_');
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: response.bodyBytes,
        mimeType: book['file_type'] == 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        dialogTitle: 'Enregistrer le document pour le vérifier',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document prêt à être examiné.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Téléchargement impossible : $error');
      }
    }
  }

  Future<void> _saveCommission() async {
    final percent = double.tryParse(_commissionController.text.trim());
    if (percent == null || percent < 0 || percent > 100) {
      setState(() => _error = 'Le taux doit être compris entre 0 et 100 %.');
      return;
    }
    setState(() {
      _isSavingCommission = true;
      _error = null;
    });
    try {
      final result = await widget.api.setCommission(percent);
      if (!mounted) return;
      setState(() {
        _commission = result;
        _isSavingCommission = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Commission enregistrée.')));
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _isSavingCommission = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _commission == null) {
      return _EmptyPage(
        icon: Icons.error_outline,
        title: 'Administration indisponible',
        message: _error!,
        buttonLabel: 'Réessayer',
        onPressed: _refresh,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Administration',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          if (_error != null)
            ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text(_error!),
            ),
          _sectionHeader('Comptes auteurs à valider', _users.length),
          if (_users.isEmpty)
            const ListTile(title: Text('Aucune demande en attente.')),
          for (final user in _users)
            Card(
              child: ListTile(
                title: Text(user['displayName'] as String? ?? 'Auteur'),
                subtitle: Text(user['email'] as String? ?? ''),
                trailing: IconButton(
                  tooltip: 'Valider le compte',
                  onPressed: () => _activateUser(user),
                  icon: const Icon(Icons.check_circle_outline),
                ),
              ),
            ),
          _sectionHeader('Livres publiés', _books.length),
          if (_books.isEmpty)
            const ListTile(title: Text('Aucun livre publié.')),
          for (final book in _books)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book['title'] as String? ?? 'Livre',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Auteur : ${book['author_name'] ?? ''} · '
                      '${book['original_file_name'] ?? ''}',
                    ),
                    Text(
                      '${book['price_amount'] ?? ''} ${book['currency'] ?? ''} · '
                      '${book['file_type'] ?? ''} · '
                      '${book['file_size_bytes'] ?? ''} octets',
                    ),
                    Text(book['description'] as String? ?? ''),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _downloadBook(book),
                            child: const Text('Télécharger pour imprimer'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _removeBook(book),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Retirer du catalogue'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          _sectionHeader('Paiement des livres', null),
          Text(
            '${_paymentProvider?['provider'] ?? 'FedaPay'} · '
            '${_paymentProvider?['environment'] ?? 'sandbox'} · '
            '${_paymentProvider?['currency'] ?? 'XOF'}',
          ),
          const SizedBox(height: 6),
          Text(
            _paymentProvider?['configured'] == true
                ? 'La clé est configurée sur le serveur. Les encaissements sont traités par le compte marchand FedaPay.'
                : 'Ajoutez une nouvelle clé secrète dans backend/.env puis redémarrez l’API.',
            style: TextStyle(
              color: _paymentProvider?['configured'] == true
                  ? const Color(0xFF647660)
                  : Colors.deepOrange,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Les commissions sont calculées à chaque vente. Les versements aux auteurs restent manuels.',
            style: TextStyle(color: Color(0xFF778397), fontSize: 12),
          ),
          _sectionHeader('Commission', null),
          TextField(
            controller: _commissionController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Part de la plateforme (%)',
              helperText: _commission?['configured'] == true
                  ? 'Taux actuellement configuré.'
                  : '0 % sera appliqué tant qu’aucun taux n’est configuré.',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isSavingCommission ? null : _saveCommission,
            child: const Text('Enregistrer le taux'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int? count) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        count == null ? title : '$title ($count)',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyPage extends StatelessWidget {
  const _EmptyPage({
    required this.icon,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: const Color(0xFF647660)),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF28372D),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF696B64), height: 1.5),
          ),
          if (buttonLabel != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
          ],
        ],
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _BookCover(book: book, width: 142)),
            const SizedBox(height: 8),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              book.author,
              style: const TextStyle(color: Color(0xFF77766F), fontSize: 13),
            ),
            if (book.id != null)
              Text(
                '${book.price} ${book.currency}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF647660),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book, required this.width, this.height});

  final Book book;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final coverUrl = book.coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: width,
        height: height,
        child: coverUrl == null
            ? ColoredBox(
                color: book.color,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.auto_stories, color: Colors.white),
                        const SizedBox(height: 8),
                        Text(
                          book.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: book.color,
                  child: const Center(
                    child: Icon(Icons.image_not_supported, color: Colors.white),
                  ),
                ),
              ),
      ),
    );
  }
}

class Book {
  const Book({
    required this.title,
    required this.author,
    required this.color,
    this.id,
    this.price,
    this.currency,
    this.fileType,
    this.coverUrl,
  });

  factory Book.fromApi(Map<String, dynamic> data) {
    final id = data['id'];
    final price = data['price_amount'];
    return Book(
      id: id is num ? id.toInt() : null,
      title: data['title'] as String? ?? 'Livre sans titre',
      author: data['author_name'] as String? ?? 'Auteur',
      color: const Color(0xFF62745B),
      price: price?.toString(),
      currency: data['currency'] as String? ?? '',
      fileType: data['file_type'] as String?,
      coverUrl: id is num && data['cover_mime_type'] is String
          ? '$apiBaseUrl/books/${id.toInt()}/cover'
          : null,
    );
  }

  final int? id;
  final String title;
  final String author;
  final Color color;
  final String? price;
  final String? currency;
  final String? fileType;
  final String? coverUrl;
}
