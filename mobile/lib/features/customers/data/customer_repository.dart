import '../../../core/network/api_client.dart';
import '../domain/customer.dart';

class CustomerRepository {
  CustomerRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Customer>> list({String search = ''}) async {
    final query = search.trim();
    final path = query.isEmpty
        ? 'customers/'
        : 'customers/search/?search=${Uri.encodeQueryComponent(query)}';
    final data = await _apiClient.get(path);
    final rows = data is List
        ? data
        : (data as Map<String, dynamic>)['results'];
    if (rows is! List) {
      throw const FormatException('Unexpected customer list response.');
    }
    return rows
        .map((row) => Customer.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  Future<Customer> get(int customerId) async => Customer.fromJson(
    Map<String, dynamic>.from(
      await _apiClient.get('customers/$customerId/') as Map,
    ),
  );

  Future<CustomerBalance> getBalance(int customerId) async =>
      CustomerBalance.fromJson(
        Map<String, dynamic>.from(
          await _apiClient.get('customers/$customerId/balance/') as Map,
        ),
      );

  Future<List<CustomerLedgerTransaction>> getTransactions(
    int customerId,
  ) async {
    final data = await _apiClient.get('customers/$customerId/transactions/');
    if (data is! List) {
      throw const FormatException('Unexpected customer transaction response.');
    }
    return data
        .map(
          (row) => CustomerLedgerTransaction.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<Customer> create({
    required Customer customer,
    String? openingBalanceAmount,
    String? openingBalanceSide,
  }) async {
    final payload = customer.toJson();
    if (openingBalanceAmount != null &&
        openingBalanceAmount.trim().isNotEmpty) {
      final amount = openingBalanceAmount.trim();
      payload['opening_balance_amount'] = amount;
      if (amount.replaceAll(RegExp(r'[.0]'), '').isNotEmpty) {
        payload['opening_balance_side'] = openingBalanceSide;
      }
    }
    return Customer.fromJson(
      Map<String, dynamic>.from(
        await _apiClient.post('customers/', body: payload) as Map,
      ),
    );
  }

  Future<Customer> update(Customer customer) async => Customer.fromJson(
    Map<String, dynamic>.from(
      await _apiClient.patch(
            'customers/${customer.id}/',
            body: customer.toJson(),
          )
          as Map,
    ),
  );

  void close() => _apiClient.close();
}
