import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/backend/backend.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../shared/mascot/mascot.dart';
import '../../shared/ui.dart';
import 'assistant_tools.dart';
import 'offline_assistant.dart';

/// Opens the Tap A Ride assistant: a sheet on phones, a side panel on wide screens.
Future<void> openAssistant(BuildContext context, {String? prompt}) {
  final partner = context.read<AppState>().isPartner;
  if (isWide(context, 900)) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close assistant',
      barrierColor: const Color(0x3306331F),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, a, b) => Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: AppColors.surface,
            elevation: 12,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(width: 440, child: AssistantView(partner: partner, initialPrompt: prompt)),
          ),
        ),
      ),
      // Enters and leaves along the same path (from the right), critically damped.
      transitionBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(position: Tween(begin: const Offset(0.12, 0), end: Offset.zero).animate(curved), child: FadeTransition(opacity: curved, child: child));
      },
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(heightFactor: 0.92, child: AssistantView(partner: partner, initialPrompt: prompt)),
  );
}

/// Floating entry point used on the rider home and in the partner portal.
class AssistantButton extends StatelessWidget {
  const AssistantButton({super.key});

  @override
  Widget build(BuildContext context) {
    final partner = context.read<AppState>().isPartner;
    return FloatingActionButton.extended(
      heroTag: 'assistant',
      onPressed: () => openAssistant(context),
      backgroundColor: AppColors.forest,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.auto_awesome_rounded),
      label: Text(partner ? 'Ask AI analyst' : 'Ask Tap A Ride'),
    );
  }
}

class _Line {
  _Line.user(this.text) : role = 'user', card = null, activity = null;
  _Line.assistant(this.text) : role = 'assistant', card = null, activity = null;
  _Line.card(this.card) : role = 'card', text = '', activity = null;
  _Line.activity(this.activity) : role = 'activity', text = '', card = null;
  _Line.error(this.text) : role = 'error', card = null, activity = null;
  _Line.note(this.activity) : role = 'note', text = '', card = null;

  final String role;
  final String text;
  final AssistantCard? card;
  String? activity;
}

class AssistantView extends StatefulWidget {
  const AssistantView({super.key, required this.partner, this.initialPrompt});
  final bool partner;
  final String? initialPrompt;

  @override
  State<AssistantView> createState() => _AssistantViewState();
}

class _AssistantViewState extends State<AssistantView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _lines = <_Line>[];
  List<dynamic> _history = const [];
  bool _busy = false;
  MascotMood _mood = MascotMood.wave;
  bool _offline = false;

  List<String> get _starters => widget.partner
      ? const ['How are we doing this week?', 'Which vehicles need attention?', 'Which routes have the most demand?', 'What is waiting for review?']
      : const ['Get me to Maitama by 8am', 'When should I leave for my next trip?', 'Book an electric car from Wuse 2 to Jabi', 'Any shared rides home to Gwarinpa?'];

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt != null) WidgetsBinding.instance.addPostFrameCallback((_) => _send(widget.initialPrompt!));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    });
  }

  Map<String, Object?> _context(AppState state) {
    final user = state.user!;
    return {
      'now_local': state.now.toIso8601String(),
      'weekday': Fmt.weekday(state.now),
      'name': user.firstName,
      'role': user.role.label,
      if (!state.isPartner) 'tap_card_balance_naira': state.wallet?.balance,
      if (!state.isPartner && state.upcomingTrips.isNotEmpty) 'next_trip': '${state.upcomingTrips.first.origin} → ${state.upcomingTrips.first.destination} ${Fmt.dayTime(state.upcomingTrips.first.departureAt)} (booking ${state.upcomingTrips.first.id})',
      if (state.isPartner && user.providerId != null) 'organisation': state.providerById(user.providerId)?.name,
    };
  }

  Future<void> _send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _busy) return;
    final state = context.read<AppState>();
    final tools = AssistantTools(state, context, onCard: (card) {
      if (!mounted) return;
      setState(() => _lines.add(_Line.card(card)));
      if (card is BookingCard) setState(() => _mood = MascotMood.celebrate);
      _toBottom();
    });
    _input.clear();
    setState(() {
      _busy = true;
      _mood = MascotMood.think;
      _lines.add(_Line.user(message));
    });
    _toBottom();

    final persona = widget.partner ? 'partner' : 'rider';
    // The judges' demo has no account on the AI service: Tapi answers on the device straight away.
    if (_offline || state.backend.isDemo) {
      _offline = true;
      return _answerOffline(state, tools, message);
    }
    try {
      AssistantStep step;
      try {
        step = await state.api.assistant(persona: persona, history: _history, text: message, context: _context(state));
      } on BackendException {
        // The AI service is unreachable or not configured: answer on the device instead
        // (also mid-conversation, so the rider never ends on an error).
        _offline = true;
        _history = const [];
        if (mounted) setState(() => _lines.add(_Line.note('Quick answers on your device')));
        await _answerOffline(state, tools, message);
        return;
      }
      // Tool loop: run what the model asks for, send results back, until it answers in text.
      for (var round = 0; round < 6 && step.toolCalls.isNotEmpty; round++) {
        _history = step.history;
        if (step.text.isNotEmpty && mounted) setState(() => _lines.add(_Line.assistant(step.text)));
        final results = <Map<String, Object?>>[];
        for (final call in step.toolCalls) {
          final activity = _Line.activity('${AssistantTools.label(call.name)}…');
          if (mounted) setState(() => _lines.add(activity));
          _toBottom();
          Object? result;
          try {
            result = await tools.run(call);
          } catch (e) {
            result = {'error': '$e'};
          }
          if (mounted) setState(() => _lines.remove(activity));
          results.add({'id': call.id, 'name': call.name, 'result': result});
        }
        if (!mounted) return;
        step = await state.api.assistant(persona: persona, history: _history, toolResults: results);
      }
      _history = step.history;
      if (mounted && step.text.isNotEmpty) setState(() => _lines.add(_Line.assistant(step.text)));
      if (mounted && _mood != MascotMood.celebrate) setState(() => _mood = MascotMood.idle);
    } on BackendException catch (e) {
      if (mounted) setState(() => _lines.add(_Line.error(e.message)));
      if (mounted) setState(() => _mood = MascotMood.sleep);
    } finally {
      if (mounted) setState(() => _busy = false);
      _toBottom();
    }
  }

  Future<void> _answerOffline(AppState state, AssistantTools tools, String message) async {
    try {
      final reply = await OfflineAssistant(state, tools).answer(message, partner: widget.partner);
      if (mounted) {
        setState(() {
          _lines.add(_Line.assistant(reply));
          if (_mood != MascotMood.celebrate) _mood = MascotMood.idle;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _lines.add(_Line.error('Sorry, that did not work: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
      _toBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = context.watch<AppState>();
    final empty = _lines.isEmpty;
    return Column(children: [
      // Header with Tapi
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(children: [
          Mascot(mood: _mood, size: 64),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.partner ? 'AI analyst' : 'Tapi · your ride assistant', style: text.titleLarge),
              Text(_busy ? 'Thinking…' : (widget.partner ? 'Ask about routes, vehicles, revenue and demand' : 'Plan trips, book seats, set reminders'), style: text.bodySmall),
            ]),
          ),
          IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      const Divider(),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          children: [
            if (empty) ...[
              Text(
                widget.partner ? 'Hi ${state.user?.firstName ?? ''}. What would you like to know about your operation?' : 'Hi ${state.user?.firstName ?? ''}! Where are you going? I can find the route, book your seat and remind you when to leave.',
                style: text.bodyLarge?.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in _starters) ActionChip(label: Text(s), onPressed: () => _send(s), avatar: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.forest)),
              ]),
            ],
            for (final line in _lines) Padding(padding: const EdgeInsets.only(bottom: 10), child: _LineView(line: line)),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !_busy,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: widget.partner ? 'Ask about your operation…' : 'Where do you want to go?',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.lineStrong)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.forest, width: 1.8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: _busy ? null : () => _send(_input.text),
              style: IconButton.styleFrom(backgroundColor: AppColors.forest, foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_upward_rounded),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _LineView extends StatelessWidget {
  const _LineView({required this.line});
  final _Line line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    switch (line.role) {
      case 'user':
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(6))),
            child: Text(line.text, style: text.bodyMedium?.copyWith(color: Colors.white)),
          ),
        );
      case 'assistant':
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(6))),
            child: SelectableText(line.text, style: text.bodyMedium?.copyWith(color: AppColors.ink)),
          ),
        );
      case 'activity':
        return Row(children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(line.activity ?? '', style: text.labelMedium?.copyWith(color: AppColors.muted)),
        ]);
      case 'note':
        return Row(children: [
          const Icon(Icons.bolt_rounded, size: 16, color: AppColors.leafText),
          const SizedBox(width: 8),
          Text(line.activity ?? '', style: text.labelMedium?.copyWith(color: AppColors.muted)),
        ]);
      case 'error':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(line.text, style: const TextStyle(color: Color(0xFF7A231A), fontWeight: FontWeight.w600))),
          ]),
        );
      default:
        return _CardView(card: line.card!);
    }
  }
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card});
  final AssistantCard card;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return switch (card) {
      RoutesCard(:final routes) => Column(children: [
          for (final r in routes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Panel(
                shadow: false,
                padding: const EdgeInsets.all(12),
                onTap: () => context.push('/ride/${r.id}'),
                child: Row(children: [
                  Expanded(child: RouteStrip(origin: r.name ?? r.origin, destination: r.name == null ? r.destination : r.mode.label, dense: true, stops: r.stops.length)),
                  Text(Fmt.naira(r.fare), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forest)),
                ]),
              ),
            ),
        ]),
      BookingCard(:final booking) => Panel(
          color: AppColors.forest,
          border: false,
          onTap: () => context.push('/ticket/${booking.id}'),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.leaf),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Booked · ${booking.ticketCode}', style: text.titleSmall?.copyWith(color: Colors.white)),
                Text('${booking.origin} → ${booking.destination} · ${Fmt.dayTime(booking.departureAt)}', style: text.bodySmall?.copyWith(color: AppColors.onForestMuted)),
              ]),
            ),
            Text('Ticket', style: text.labelLarge?.copyWith(color: Colors.white)),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
      TripPlanCard(:final from, :final to, :final plan) => Panel(
          shadow: false,
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RouteStrip(origin: from, destination: to, dense: true),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.directions_car_rounded, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Text('${plan.minutes} min · ${plan.distanceText}', style: text.titleSmall),
              const SizedBox(width: 6),
              Flexible(child: Text(plan.label, style: text.bodySmall, overflow: TextOverflow.ellipsis)),
            ]),
          ]),
        ),
    };
  }
}
