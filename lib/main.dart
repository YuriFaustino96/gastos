import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GastosApp());
}

class GastosApp extends StatelessWidget {
  const GastosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gestão de Gastos',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF6366F1),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          surfaceTintColor: Colors.white,
          color: Colors.white,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFE0E7FF),
          labelStyle: const TextStyle(color: Color(0xFF4F46E5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: const FinanceHome(),
    );
  }
}

/// ======== CATEGORIAS ========

enum TipoCategoria { receita, despesa }

extension TipoCategoriaX on TipoCategoria {
  String get label => this == TipoCategoria.receita ? 'Receita' : 'Despesa';
  static TipoCategoria fromName(String s) =>
      s == 'receita' ? TipoCategoria.receita : TipoCategoria.despesa;
}

class CategoriaModel {
  final String id;
  final String nome;
  final TipoCategoria tipo;
  final int colorValue;
  final int iconCodePoint;

  CategoriaModel({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.colorValue,
    required this.iconCodePoint,
  });

  Color get color => Color(colorValue);
  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'tipo': tipo.name,
        'colorValue': colorValue,
        'iconCodePoint': iconCodePoint,
      };

  factory CategoriaModel.fromJson(Map<String, dynamic> json) => CategoriaModel(
        id: json['id'] as String,
        nome: json['nome'] as String,
        tipo: TipoCategoriaX.fromName(json['tipo'] as String),
        colorValue: json['colorValue'] as int,
        iconCodePoint: json['iconCodePoint'] as int,
      );
}

/// ======== TRANSAÇÕES / MESES ========

class Transacao {
  final String descricao;
  final double valor;
  final bool isReceita;
  final String categoriaId;
  final DateTime criadoEm;

  Transacao({
    required this.descricao,
    required this.valor,
    required this.isReceita,
    required this.categoriaId,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'descricao': descricao,
        'valor': valor,
        'isReceita': isReceita,
        'categoriaId': categoriaId,
        'criadoEm': criadoEm.toIso8601String(),
      };

  factory Transacao.fromJson(Map<String, dynamic> json) => Transacao(
        descricao: json['descricao'] as String,
        valor: (json['valor'] as num).toDouble(),
        isReceita: json['isReceita'] as bool,
        categoriaId: json['categoriaId'] as String,
        criadoEm: DateTime.parse(json['criadoEm'] as String),
      );
}

class MesFinanceiro {
  final int ano;
  final int mes; // 1..12
  final List<Transacao> transacoes;

  MesFinanceiro({
    required this.ano,
    required this.mes,
    List<Transacao>? transacoes,
  }) : transacoes = transacoes ?? [];

  double get totalReceitas =>
      transacoes.where((t) => t.isReceita).fold(0.0, (acc, t) => acc + t.valor);

  double get totalDespesas =>
      transacoes.where((t) => !t.isReceita).fold(0.0, (acc, t) => acc + t.valor);

  double get saldoMes => totalReceitas - totalDespesas;

  Map<String, dynamic> toJson() => {
        'ano': ano,
        'mes': mes,
        'transacoes': transacoes.map((t) => t.toJson()).toList(),
      };

  factory MesFinanceiro.fromJson(Map<String, dynamic> json) => MesFinanceiro(
        ano: json['ano'] as int,
        mes: json['mes'] as int,
        transacoes: (json['transacoes'] as List<dynamic>)
            .map((e) => Transacao.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// ======== REPO (SharedPreferences) ========

class FinanceRepo {
  static const _storageKey = 'finance_por_ano_v3';
  static const _catsKey = 'finance_categorias_v3';

  Future<Map<int, List<MesFinanceiro>>> carregarTudo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return {};

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final result = <int, List<MesFinanceiro>>{};

    decoded.forEach((anoStr, mesesList) {
      final ano = int.tryParse(anoStr);
      if (ano == null) return;
      final meses = (mesesList as List<dynamic>)
          .map((e) => MesFinanceiro.fromJson(e as Map<String, dynamic>))
          .toList();
      meses.sort((a, b) => a.mes.compareTo(b.mes));
      result[ano] = meses;
    });

    return result;
  }

  Future<void> salvarTudo(Map<int, List<MesFinanceiro>> data) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{};
    data.forEach((ano, meses) {
      encoded['$ano'] = meses.map((m) => m.toJson()).toList();
    });
    await prefs.setString(_storageKey, jsonEncode(encoded));
  }

  Future<List<CategoriaModel>> carregarCategorias() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_catsKey);

    if (raw == null || raw.trim().isEmpty) {
      final defaults = _categoriasPadrao();
      await salvarCategorias(defaults);
      return defaults;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    final cats = decoded
        .map((e) => CategoriaModel.fromJson(e as Map<String, dynamic>))
        .toList();

    if (cats.isEmpty) {
      final defaults = _categoriasPadrao();
      await salvarCategorias(defaults);
      return defaults;
    }
    return cats;
  }

  Future<void> salvarCategorias(List<CategoriaModel> cats) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(cats.map((c) => c.toJson()).toList());
    await prefs.setString(_catsKey, raw);
  }

  List<CategoriaModel> _categoriasPadrao() {
    return [
      // RECEITAS
      CategoriaModel(
        id: 'rec_salario',
        nome: 'Salário',
        tipo: TipoCategoria.receita,
        colorValue: const Color(0xFF10B981).value,
        iconCodePoint: Icons.attach_money.codePoint,
      ),
      CategoriaModel(
        id: 'rec_outros',
        nome: 'Outros',
        tipo: TipoCategoria.receita,
        colorValue: const Color(0xFF14B8A6).value,
        iconCodePoint: Icons.add_card.codePoint,
      ),

      // DESPESAS
      CategoriaModel(
        id: 'des_mercado',
        nome: 'Mercado',
        tipo: TipoCategoria.despesa,
        colorValue: const Color(0xFFF97316).value,
        iconCodePoint: Icons.shopping_cart.codePoint,
      ),
      CategoriaModel(
        id: 'des_transporte',
        nome: 'Transporte',
        tipo: TipoCategoria.despesa,
        colorValue: const Color(0xFF3B82F6).value,
        iconCodePoint: Icons.directions_bus.codePoint,
      ),
      CategoriaModel(
        id: 'des_contas',
        nome: 'Contas',
        tipo: TipoCategoria.despesa,
        colorValue: const Color(0xFF8B5CF6).value,
        iconCodePoint: Icons.receipt_long.codePoint,
      ),
      CategoriaModel(
        id: 'des_lazer',
        nome: 'Lazer',
        tipo: TipoCategoria.despesa,
        colorValue: const Color(0xFFEC4899).value,
        iconCodePoint: Icons.movie.codePoint,
      ),
      CategoriaModel(
        id: 'des_saude',
        nome: 'Saúde',
        tipo: TipoCategoria.despesa,
        colorValue: const Color(0xFFEF4444).value,
        iconCodePoint: Icons.medical_services.codePoint,
      ),
      CategoriaModel(
        id: 'des_educacao',
        nome: 'Educação',
        tipo: TipoCategoria.despesa,
        colorValue: const Color(0xFF6366F1).value,
        iconCodePoint: Icons.school.codePoint,
      ),
      CategoriaModel(
        id: 'des_outros',
        nome: 'Outros',
        tipo: TipoCategoria.despesa,
        colorValue: const Color(0xFF6B7280).value,
        iconCodePoint: Icons.category.codePoint,
      ),
    ];
  }
}

/// ======== HOME ========

class FinanceHome extends StatefulWidget {
  const FinanceHome({super.key});

  @override
  State<FinanceHome> createState() => _FinanceHomeState();
}

class _FinanceHomeState extends State<FinanceHome> {
  final _repo = FinanceRepo();

  Map<int, List<MesFinanceiro>> _dataPorAno = {};
  List<CategoriaModel> _categorias = [];
  late int _anoSelecionado;

  static const _mesNomes = [
    'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final loaded = await _repo.carregarTudo();
    final cats = await _repo.carregarCategorias();

    final anoAtual = DateTime.now().year;

    loaded.putIfAbsent(anoAtual, () => _criarAno(anoAtual));
    loaded[anoAtual] = _garantir12Meses(anoAtual, loaded[anoAtual]!);

    setState(() {
      _dataPorAno = loaded;
      _categorias = cats;
      _anoSelecionado = anoAtual;
    });

    await _persistAll();
  }

  List<MesFinanceiro> _criarAno(int ano) =>
      List.generate(12, (i) => MesFinanceiro(ano: ano, mes: i + 1));

  List<MesFinanceiro> _garantir12Meses(int ano, List<MesFinanceiro> meses) {
    final map = {for (final m in meses) m.mes: m};
    return List.generate(12, (i) => map[i + 1] ?? MesFinanceiro(ano: ano, mes: i + 1));
  }

  Future<void> _persistAll() async {
    await _repo.salvarTudo(_dataPorAno);
    await _repo.salvarCategorias(_categorias);
  }

  List<MesFinanceiro> get _mesesAno => _dataPorAno[_anoSelecionado]!;

  double _saldoAcumuladoAteMes(int mesIndex) {
    double acc = 0;
    for (int i = 0; i <= mesIndex; i++) {
      acc += _mesesAno[i].saldoMes;
    }
    return acc;
  }

  CategoriaModel? _catById(String id) {
    try {
      return _categorias.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  void _gerenciarCategorias() async {
    final result = await showDialog<List<CategoriaModel>>(
      context: context,
      builder: (ctx) => GerenciadorCategoriasDialog(categorias: _categorias),
    );

    if (result != null) {
      setState(() => _categorias = result);
      await _persistAll();
    }
  }

  void _criarAnoNovo() async {
    final novoAno = (_dataPorAno.keys.isEmpty
            ? DateTime.now().year
            : (_dataPorAno.keys.toList()..sort()).last) +
        1;

    setState(() {
      _dataPorAno[novoAno] = _criarAno(novoAno);
      _anoSelecionado = novoAno;
    });

    await _persistAll();
  }

  Future<void> _removerAnoAtual() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar ano?'),
        content: Text(
          'Tem certeza que deseja apagar o ano $_anoSelecionado?\nIsso apaga TODOS os meses e lançamentos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _dataPorAno.remove(_anoSelecionado);

      if (_dataPorAno.isNotEmpty) {
        final anos = _dataPorAno.keys.toList()..sort();
        _anoSelecionado = anos.last;
      } else {
        final anoAtual = DateTime.now().year;
        _dataPorAno[anoAtual] = _criarAno(anoAtual);
        _anoSelecionado = anoAtual;
      }
    });

    await _persistAll();
  }

  Future<void> _addTransacao(int mesIndex, bool isReceita) async {
    final catsFiltradas = _categorias
        .where((c) => c.tipo == (isReceita ? TipoCategoria.receita : TipoCategoria.despesa))
        .toList();

    if (catsFiltradas.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Crie uma categoria de ${isReceita ? "Receita" : "Despesa"} primeiro.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<Transacao>(
      context: context,
      builder: (ctx) => AddTransacaoDialog(categorias: catsFiltradas),
    );

    if (result != null) {
      setState(() => _mesesAno[mesIndex].transacoes.add(result));
      await _persistAll();
    }
  }

  Future<void> _removeTransacao(int mesIndex, int transIndex) async {
    setState(() => _mesesAno[mesIndex].transacoes.removeAt(transIndex));
    await _persistAll();
  }

  @override
  Widget build(BuildContext context) {
    if (_dataPorAno.isEmpty || _categorias.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final anos = _dataPorAno.keys.toList()..sort();

    return DefaultTabController(
      length: 12,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestão de Gastos', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: TabBar(
              isScrollable: true,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              tabs: List.generate(12, (i) => Tab(text: _mesNomes[i])),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Categorias',
              onPressed: _gerenciarCategorias,
              icon: const Icon(Icons.grid_view),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _anoSelecionado,
                  dropdownColor: const Color(0xFF6366F1),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  items: anos.map((a) => DropdownMenuItem(value: a, child: Text('$a'))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _anoSelecionado = v);
                  },
                ),
              ),
            ),
            IconButton(
              tooltip: 'Novo ano',
              onPressed: _criarAnoNovo,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: 'Apagar ano',
              onPressed: _removerAnoAtual,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: TabBarView(
          children: List.generate(12, (mesIndex) {
            final mes = _mesesAno[mesIndex];
            final saldoAcum = _saldoAcumuladoAteMes(mesIndex);

            return MesPage(
              mes: mes,
              saldoAcumulado: saldoAcum,
              catById: _catById,
              onAddReceita: () => _addTransacao(mesIndex, true),
              onAddDespesa: () => _addTransacao(mesIndex, false),
              onRemove: (tIndex) => _removeTransacao(mesIndex, tIndex),
              todosMesesDoAno: _mesesAno,
            );
          }),
        ),
      ),
    );
  }
}

/// ======== PAGE MÊS ========

class MesPage extends StatelessWidget {
  final MesFinanceiro mes;
  final double saldoAcumulado;
  final CategoriaModel? Function(String id) catById;
  final VoidCallback onAddReceita;
  final VoidCallback onAddDespesa;
  final void Function(int transIndex) onRemove;
  final List<MesFinanceiro> todosMesesDoAno;

  const MesPage({
    super.key,
    required this.mes,
    required this.saldoAcumulado,
    required this.catById,
    required this.onAddReceita,
    required this.onAddDespesa,
    required this.onRemove,
    required this.todosMesesDoAno,
  });

  Map<String, double> _despesasPorCategoriaId() {
    final map = <String, double>{};
    for (final t in mes.transacoes.where((t) => !t.isReceita)) {
      map[t.categoriaId] = (map[t.categoriaId] ?? 0) + t.valor;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final despesasCat = _despesasPorCategoriaId();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Cabeçalho
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Mês ${mes.mes.toString().padLeft(2, '0')}/${mes.ano}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
            ),
            Row(
              children: [
                FloatingActionButton.small(
                  onPressed: onAddReceita,
                  backgroundColor: const Color(0xFF10B981),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  onPressed: onAddDespesa,
                  backgroundColor: const Color(0xFFEF4444),
                  child: const Icon(Icons.remove, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Resumo
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ResumoCard(
                label: 'Receitas',
                valor: 'R\$ ${mes.totalReceitas.toStringAsFixed(2)}',
                cor: const Color(0xFF10B981),
                icon: Icons.trending_up,
              ),
              const SizedBox(width: 12),
              _ResumoCard(
                label: 'Despesas',
                valor: 'R\$ ${mes.totalDespesas.toStringAsFixed(2)}',
                cor: const Color(0xFFEF4444),
                icon: Icons.trending_down,
              ),
              const SizedBox(width: 12),
              _ResumoCard(
                label: 'Saldo do Mês',
                valor: 'R\$ ${mes.saldoMes.toStringAsFixed(2)}',
                cor: mes.saldoMes >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                icon: Icons.account_balance_wallet,
              ),
              const SizedBox(width: 12),
              _ResumoCard(
                label: 'Saldo Acumulado',
                valor: 'R\$ ${saldoAcumulado.toStringAsFixed(2)}',
                cor: saldoAcumulado >= 0 ? const Color(0xFF6366F1) : const Color(0xFFEF4444),
                icon: Icons.savings,
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        Text('Análise Visual', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        // Pizza: despesas por categoria (com cor)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 250,
              child: despesasCat.isEmpty
                  ? const Center(child: Text('Sem despesas para gerar gráfico'))
                  : PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 50,
                        sections: despesasCat.entries.map((e) {
                          final cat = catById(e.key);
                          final nome = cat?.nome ?? 'Categoria';
                          final cor = cat?.color ?? Colors.grey;
                          final value = e.value;

                          return PieChartSectionData(
                            value: value,
                            color: cor,
                            title: '$nome\nR\$ ${value.toStringAsFixed(0)}',
                            radius: 80,
                            titleStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Barras: receitas x despesas
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          final label = (i == 0) ? 'Receitas' : 'Despesas';
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: mes.totalReceitas,
                          color: const Color(0xFF10B981),
                          width: 40,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        )
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: mes.totalDespesas,
                          color: const Color(0xFFEF4444),
                          width: 40,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Linha: saldo do ano mês a mês
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 260,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 1 || i > 12) return const SizedBox.shrink();
                          return Text('$i', style: const TextStyle(fontSize: 11));
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(12, (i) {
                        final m = todosMesesDoAno[i];
                        return FlSpot((i + 1).toDouble(), m.saldoMes);
                      }),
                      isCurved: true,
                      dotData: const FlDotData(show: false),
                      barWidth: 3,
                      color: const Color(0xFF6366F1),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF6366F1).withOpacity(0.18),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 18),
        Text('Lançamentos', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        if (mes.transacoes.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nenhum lançamento neste mês')),
            ),
          )
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: mes.transacoes.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (_, tIndex) {
                final t = mes.transacoes[tIndex];
                final cat = catById(t.categoriaId);
                final cor = cat?.color ?? Colors.grey;
                final icon = cat?.icon ?? Icons.category;

                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: cor, size: 24),
                  ),
                  title: Text(t.descricao, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    cat?.nome ?? 'Categoria removida',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                  trailing: Text(
                    '${t.isReceita ? '+' : '-'} R\$ ${t.valor.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: t.isReceita ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                  ),
                  onLongPress: () => _showRemoveDialog(context, tIndex),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showRemoveDialog(BuildContext context, int tIndex) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover lançamento?'),
        content: const Text('Tem certeza que deseja remover este lançamento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              onRemove(tIndex);
              Navigator.pop(ctx);
            },
            child: const Text('Remover', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _ResumoCard extends StatelessWidget {
  final String label;
  final String valor;
  final Color cor;
  final IconData icon;

  const _ResumoCard({
    required this.label,
    required this.valor,
    required this.cor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12)),
              Icon(icon, color: cor, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(valor, style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

/// ======== DIALOG: ADD TRANSAÇÃO ========

class AddTransacaoDialog extends StatefulWidget {
  final List<CategoriaModel> categorias;

  const AddTransacaoDialog({super.key, required this.categorias});

  @override
  State<AddTransacaoDialog> createState() => _AddTransacaoDialogState();
}

class _AddTransacaoDialogState extends State<AddTransacaoDialog> {
  late final TextEditingController _descricaoCtrl;
  late final TextEditingController _valorCtrl;
  late CategoriaModel _categoriaSelecionada;

  @override
  void initState() {
    super.initState();
    _descricaoCtrl = TextEditingController();
    _valorCtrl = TextEditingController();
    _categoriaSelecionada = widget.categorias.first;
  }

  @override
  void dispose() {
    _descricaoCtrl.dispose();
    _valorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.categorias.first.tipo == TipoCategoria.receita ? 'Nova Receita (+)' : 'Nova Despesa (–)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _descricaoCtrl,
              decoration: InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valorCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Valor',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixText: 'R\$ ',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CategoriaModel>(
              value: _categoriaSelecionada,
              items: widget.categorias
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Row(
                          children: [
                            Icon(c.icon, color: c.color),
                            const SizedBox(width: 8),
                            Text(c.nome),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (c) => setState(() => _categoriaSelecionada = c!),
              decoration: InputDecoration(
                labelText: 'Categoria',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final desc = _descricaoCtrl.text.trim();
            final valor = double.tryParse(_valorCtrl.text.trim().replaceAll(',', '.')) ?? 0;

            if (desc.isEmpty || valor <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Preencha descrição e valor válido.')),
              );
              return;
            }

            final transacao = Transacao(
              descricao: desc,
              valor: valor,
              isReceita: _categoriaSelecionada.tipo == TipoCategoria.receita, // ✅ correto
              categoriaId: _categoriaSelecionada.id,
            );
            Navigator.pop(context, transacao);
          },
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

/// ======== DIALOG: GERENCIAR CATEGORIAS (ADD/DELETE) ========

class GerenciadorCategoriasDialog extends StatefulWidget {
  final List<CategoriaModel> categorias;

  const GerenciadorCategoriasDialog({super.key, required this.categorias});

  @override
  State<GerenciadorCategoriasDialog> createState() => _GerenciadorCategoriasDialogState();
}

class _GerenciadorCategoriasDialogState extends State<GerenciadorCategoriasDialog> {
  late List<CategoriaModel> _cats;

  @override
  void initState() {
    super.initState();
    _cats = List.from(widget.categorias);
  }

  Future<void> _addCategoria() async {
    final nova = await showDialog<CategoriaModel>(
      context: context,
      builder: (_) => const AddCategoriaDialog(),
    );
    if (nova != null) {
      setState(() => _cats.add(nova));
    }
  }

  Future<void> _removerCategoria(int i) async {
    final cat = _cats[i];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar categoria?'),
        content: Text('Deseja apagar a categoria "${cat.nome}"?\n\nObs: lançamentos antigos vão aparecer como "Categoria removida".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() => _cats.removeAt(i));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categorias'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              tooltip: 'Adicionar categoria',
              icon: const Icon(Icons.add),
              onPressed: _addCategoria,
            ),
          ],
        ),
        body: ListView.separated(
          itemCount: _cats.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final cat = _cats[i];
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cat.color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(cat.icon, color: Colors.white),
              ),
              title: Text(cat.nome),
              subtitle: Text(cat.tipo.label),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _removerCategoria(i),
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Salvar',
          onPressed: () => Navigator.pop(context, _cats),
          child: const Icon(Icons.check),
        ),
      ),
    );
  }
}

/// ======== DIALOG: ADD CATEGORIA ========

class AddCategoriaDialog extends StatefulWidget {
  const AddCategoriaDialog({super.key});

  @override
  State<AddCategoriaDialog> createState() => _AddCategoriaDialogState();
}

class _AddCategoriaDialogState extends State<AddCategoriaDialog> {
  final _nomeCtrl = TextEditingController();
  TipoCategoria _tipo = TipoCategoria.despesa;

  Color _cor = const Color(0xFF3B82F6);
  IconData _icone = Icons.category;

  final _cores = <Color>[
    Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
    Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
    Colors.teal, Colors.green, Colors.lime, Colors.amber, Colors.orange,
    Colors.deepOrange, Colors.brown, Colors.grey,
  ];

  final _icones = <IconData>[
    Icons.shopping_cart,
    Icons.directions_bus,
    Icons.receipt_long,
    Icons.movie,
    Icons.medical_services,
    Icons.school,
    Icons.home,
    Icons.restaurant,
    Icons.sports_soccer,
    Icons.pets,
    Icons.phone_android,
    Icons.wifi,
    Icons.lightbulb,
    Icons.attach_money,
    Icons.credit_card,
    Icons.savings,
    Icons.category,
  ];

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova Categoria'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nomeCtrl,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TipoCategoria>(
              value: _tipo,
              items: TipoCategoria.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _tipo = v ?? _tipo),
              decoration: const InputDecoration(labelText: 'Tipo'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Cor', style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cores.map((c) {
                final selected = c.value == _cor.value;
                return InkWell(
                  onTap: () => setState(() => _cor = c),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: selected ? 3 : 1,
                        color: selected ? Colors.black : Colors.black26,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Ícone', style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 170,
              child: GridView.builder(
                itemCount: _icones.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (_, i) {
                  final ic = _icones[i];
                  final selected = ic.codePoint == _icone.codePoint;
                  return InkWell(
                    onTap: () => setState(() => _icone = ic),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          width: selected ? 2 : 1,
                          color: selected ? Colors.black : Colors.black26,
                        ),
                      ),
                      child: Icon(ic, color: _cor),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final nome = _nomeCtrl.text.trim();
            if (nome.isEmpty) return;

            final id = '${_tipo.name}_${DateTime.now().millisecondsSinceEpoch}';

            Navigator.pop(
              context,
              CategoriaModel(
                id: id,
                nome: nome,
                tipo: _tipo,
                colorValue: _cor.value,
                iconCodePoint: _icone.codePoint,
              ),
            );
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}