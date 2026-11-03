import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:application_livre/main.dart';
import 'package:application_livre/api_client.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();

  bool registered = false;
  bool hasExistingSession = true;
  bool catalogueUnavailable = false;
  bool paymentAlreadyPaid = false;
  bool resetRequested = false;
  String updatedEmail = 'reader@example.test';
  String accountType = 'reader';

  @override
  Future<String?> readToken() async => hasExistingSession ? 'test-token' : null;

  @override
  Future<Map<String, dynamic>> currentUser() async => {
    'user': {
      'id': 1,
      'email': 'reader@example.test',
      'displayName': 'Lecteur test',
      'role': accountType,
      'status': 'active',
    },
  };

  @override
  Future<Map<String, dynamic>> paymentProvider() async => {
    'provider': 'FedaPay',
    'environment': 'sandbox',
    'currency': 'XOF',
    'configured': false,
    'automaticPayouts': false,
  };

  @override
  Future<Map<String, dynamic>> register({
    required String email,
    required String displayName,
    required String password,
    required String accountType,
  }) async {
    registered = true;
    this.accountType = accountType;
    return {
      'message': accountType == 'author'
          ? 'Votre demande de compte auteur est en attente de validation.'
          : 'Votre compte lecteur est créé.',
    };
  }

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return {
      'token': 'test-token',
      'user': {
        'id': 1,
        'email': email,
        'displayName': 'Lecteur test',
        'role': accountType,
        'status': 'active',
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> books({String search = ''}) async {
    if (catalogueUnavailable) {
      throw const ApiException('Catalogue indisponible.');
    }
    return [
      {
        'id': 4,
        'title': 'Livre publié',
        'description': 'Description du livre publié.',
        'price_amount': '5.00',
        'currency': 'XOF',
        'file_type': 'pdf',
        'author_name': 'Auteur test',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> createPaymentCheckout(int bookId) async {
    if (paymentAlreadyPaid) {
      return {'orderId': 19, 'alreadyPaid': true};
    }
    throw const ApiException(
      'Le paiement FedaPay n’est pas encore configuré sur le serveur.',
      statusCode: 503,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> authorBooks() async => [];

  @override
  Future<List<Map<String, dynamic>>> purchasedBooks() async => [];

  @override
  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    resetRequested = true;
    return {
      'message': 'Si cette adresse possède un compte, un lien a été envoyé.',
    };
  }

  @override
  Future<Map<String, dynamic>> updateProfile({
    required String currentPassword,
    String? email,
    String? newPassword,
  }) async {
    updatedEmail = email ?? updatedEmail;
    return {
      'user': {
        'id': 1,
        'email': updatedEmail,
        'displayName': 'Lecteur test',
        'role': accountType,
        'status': 'active',
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> adminBooks({
    String status = 'approved',
  }) async => [];

  @override
  Future<List<Map<String, dynamic>>> adminUsers({
    String? status,
    String? role,
  }) async => [];

  @override
  Future<Map<String, dynamic>> commission() async => {'percent': 20};
}

ApplicationLivre _app([ApiClient? apiClient]) =>
    ApplicationLivre(apiClient: apiClient ?? _FakeApiClient());

void main() {
  testWidgets('restores a signed-in reader to the discovery page', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Votre prochaine lecture vous attend.'), findsOneWidget);
    expect(find.text('Catalogue chargé depuis le serveur.'), findsOneWidget);
    expect(find.text('Livre publié'), findsWidgets);
  });

  testWidgets('a restored online book opens the active FedaPay checkout', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Livre publié').first);
    await tester.tap(find.text('Livre publié').first);
    await tester.pumpAndSettle();

    expect(find.text('Payer avec FedaPay'), findsOneWidget);
    expect(find.text('Paiement bientôt disponible'), findsNothing);

    await tester.ensureVisible(find.text('Payer avec FedaPay'));
    await tester.tap(find.text('Payer avec FedaPay'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Le paiement FedaPay n’est pas encore configuré sur le serveur.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'payment success returns home and opens the purchased book on OK',
    (tester) async {
      final api = _FakeApiClient()..paymentAlreadyPaid = true;
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Livre publié').first);
      await tester.tap(find.text('Livre publié').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payer avec FedaPay'));
      await tester.pumpAndSettle();

      expect(find.text('Paiement réussi'), findsOneWidget);
      expect(find.text('Votre prochaine lecture vous attend.'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Paiement réussi'), findsNothing);
      expect(find.text('Livre publié'), findsWidgets);
      expect(find.text('Télécharger le livre'), findsOneWidget);
    },
  );

  testWidgets('opens the administration page for a signed-in administrator', (
    tester,
  ) async {
    final api = _FakeApiClient()..accountType = 'admin';
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('Administration'), findsWidgets);
    expect(find.text('Comptes auteurs à valider (0)'), findsOneWidget);
    expect(find.text('Livres publiés (0)'), findsOneWidget);
    expect(find.text('Chiffres clés'), findsNothing);
    expect(find.textContaining('Ventes par devise'), findsNothing);
    expect(
      find.text(
        'Les paiements, versements et le chiffrement ne sont pas encore activés.',
      ),
      findsNothing,
    );
    expect(find.text('Paiement des livres'), findsOneWidget);
    expect(find.text('FedaPay · sandbox · XOF'), findsOneWidget);
    expect(find.text('Votre prochaine lecture vous attend.'), findsNothing);
  });

  testWidgets('author page does not expose a separate payout method', (
    tester,
  ) async {
    final api = _FakeApiClient()..accountType = 'author';
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mes livres').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('poser'), findsOneWidget);
    expect(find.textContaining('MTN'), findsNothing);
    expect(find.textContaining('versement'), findsNothing);
  });

  testWidgets('opens the empty library and returns to discovery', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ma bibliothèque'));
    await tester.pumpAndSettle();

    expect(find.text('Votre bibliothèque'), findsOneWidget);
    expect(find.textContaining('achetés apparaîtront'), findsOneWidget);

    await tester.tap(find.text('Découvrir les livres'));
    await tester.pumpAndSettle();

    expect(find.text('Votre prochaine lecture vous attend.'), findsOneWidget);
  });

  testWidgets('does not show sample books when the catalogue is unavailable', (
    tester,
  ) async {
    final api = _FakeApiClient()..catalogueUnavailable = true;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('Livre publié'), findsNothing);
    expect(find.text('Le secret des pages'), findsNothing);
    expect(find.text('Les chemins du matin'), findsNothing);
    expect(find.text('La maison des mots'), findsNothing);
    expect(find.text('Catalogue indisponible.'), findsOneWidget);
  });

  testWidgets('filters books returned by the online catalogue', (tester) async {
    final api = _FakeApiClient();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.pumpAndSettle();

    expect(find.text('Livre publié'), findsNothing);
  });

  testWidgets('registers a reader and loads the server catalogue', (
    tester,
  ) async {
    final api = _FakeApiClient();
    api.hasExistingSession = false;
    await tester.pumpWidget(_app(api));

    await tester.pumpAndSettle();
    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.text('Votre prochaine lecture vous attend.'), findsNothing);
    expect(find.text('Créer un compte lecteur ou auteur'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'Lecteur test');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'reader@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'abc12345');
    await tester.ensureVisible(find.text('Créer mon compte'));
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();

    expect(api.registered, isTrue);
    expect(find.text('Votre prochaine lecture vous attend.'), findsOneWidget);
    expect(find.text('Livre publié'), findsWidgets);
    expect(
      find.textContaining('Catalogue chargé depuis le serveur.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows registration before the home page when no account exists',
    (tester) async {
      final api = _FakeApiClient()..hasExistingSession = false;
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();

      expect(find.text('Créer un compte'), findsOneWidget);
      expect(find.text('Nom affiché'), findsOneWidget);
      expect(find.text('Type de compte'), findsOneWidget);
      expect(find.text('Votre prochaine lecture vous attend.'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('keeps the background image when switching to login', (
    tester,
  ) async {
    final api = _FakeApiClient()..hasExistingSession = false;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    Finder backgroundImage() => find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == '3.jpg',
    );

    expect(backgroundImage(), findsOneWidget);
    await tester.ensureVisible(find.text('Se connecter'));
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Connexion'), findsOneWidget);
    expect(backgroundImage(), findsOneWidget);
  });

  testWidgets('requests a password reset from the login screen', (
    tester,
  ) async {
    final api = _FakeApiClient()..hasExistingSession = false;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Se connecter'));
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Mot de passe oublié ?'));
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'reader@example.test');
    await tester.tap(find.text('Envoyer le lien'));
    await tester.pumpAndSettle();

    expect(api.resetRequested, isTrue);
    expect(find.textContaining('un lien a été envoyé'), findsOneWidget);
  });

  testWidgets('updates the profile email after confirming current password', (
    tester,
  ) async {
    final api = _FakeApiClient();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier mon e-mail ou mon mot de passe'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'new-reader@example.test',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'current-password',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(api.updatedEmail, 'new-reader@example.test');
    expect(find.text('new-reader@example.test'), findsOneWidget);
  });

  testWidgets('requires at least eight characters at registration', (
    tester,
  ) async {
    final api = _FakeApiClient()..hasExistingSession = false;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Lecteur test');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'reader@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'abc1234');
    await tester.ensureVisible(find.text('Créer mon compte'));
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();

    expect(find.text('Utilisez au moins 8 caractères.'), findsOneWidget);
    expect(api.registered, isFalse);
    expect(find.text('Votre prochaine lecture vous attend.'), findsNothing);
  });
}
