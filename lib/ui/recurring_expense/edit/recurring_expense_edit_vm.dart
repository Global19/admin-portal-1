// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_styled_toast/flutter_styled_toast.dart';
import 'package:http/http.dart';
import 'package:invoiceninja_flutter/redux/document/document_actions.dart';
import 'package:redux/redux.dart';

// Project imports:
import 'package:invoiceninja_flutter/data/models/models.dart';
import 'package:invoiceninja_flutter/redux/app/app_actions.dart';
import 'package:invoiceninja_flutter/redux/app/app_state.dart';
import 'package:invoiceninja_flutter/redux/recurring_expense/recurring_expense_actions.dart';
import 'package:invoiceninja_flutter/redux/ui/ui_actions.dart';
import 'package:invoiceninja_flutter/ui/app/dialogs/error_dialog.dart';
import 'package:invoiceninja_flutter/ui/expense/edit/expense_edit.dart';
import 'package:invoiceninja_flutter/ui/expense/edit/expense_edit_vm.dart';
import 'package:invoiceninja_flutter/ui/recurring_expense/view/recurring_expense_view_vm.dart';
import 'package:invoiceninja_flutter/utils/completers.dart';
import 'package:invoiceninja_flutter/utils/localization.dart';

class RecurringExpenseEditScreen extends StatelessWidget {
  const RecurringExpenseEditScreen({Key key}) : super(key: key);
  static const String route = '/recurring_expense/edit';

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, RecurringExpenseEditVM>(
      converter: (Store<AppState> store) {
        return RecurringExpenseEditVM.fromStore(store);
      },
      builder: (context, viewModel) {
        return ExpenseEdit(
          viewModel: viewModel,
          key: ValueKey(viewModel.expense.updatedAt),
        );
      },
    );
  }
}

class RecurringExpenseEditVM extends AbstractExpenseEditVM {
  RecurringExpenseEditVM({
    AppState state,
    ExpenseEntity expense,
    Function(ExpenseEntity) onChanged,
    Function(BuildContext) onSavePressed,
    Function(BuildContext) onCancelPressed,
    bool isLoading,
    bool isSaving,
    ExpenseEntity origExpense,
    Function(BuildContext context, Completer<SelectableEntity> completer)
        onAddClientPressed,
    Function(BuildContext context, Completer<SelectableEntity> completer)
        onAddVendorPressed,
    Function(BuildContext, MultipartFile) onUploadDocument,
    Function(BuildContext, DocumentEntity, String, String) onDeleteDocument,
  }) : super(
          state: state,
          expense: expense,
          onChanged: onChanged,
          onSavePressed: onSavePressed,
          onCancelPressed: onCancelPressed,
          origExpense: origExpense,
          onAddClientPressed: onAddClientPressed,
          onAddVendorPressed: onAddVendorPressed,
          onUploadDocument: onUploadDocument,
          onDeleteDocument: onDeleteDocument,
        );

  factory RecurringExpenseEditVM.fromStore(Store<AppState> store) {
    final state = store.state;
    final recurringExpense = state.recurringExpenseUIState.editing;

    return RecurringExpenseEditVM(
      state: state,
      isLoading: state.isLoading,
      isSaving: state.isSaving,
      origExpense: state.recurringExpenseState.map[recurringExpense.id],
      expense: recurringExpense,
      onChanged: (ExpenseEntity recurringExpense) {
        store.dispatch(UpdateRecurringExpense(recurringExpense));
      },
      onAddClientPressed: (context, completer) {
        createEntity(
            context: context,
            entity: ClientEntity(),
            force: true,
            completer: completer,
            cancelCompleter: Completer<Null>()
              ..future.then((_) {
                store.dispatch(
                    UpdateCurrentRoute(RecurringExpenseEditScreen.route));
              }));
        completer.future.then((SelectableEntity client) {
          store.dispatch(UpdateCurrentRoute(RecurringExpenseEditScreen.route));
        });
      },
      onAddVendorPressed: (context, completer) {
        createEntity(
            context: context,
            entity: VendorEntity(),
            force: true,
            completer: completer,
            cancelCompleter: Completer<Null>()
              ..future.then((_) {
                store.dispatch(
                    UpdateCurrentRoute(RecurringExpenseEditScreen.route));
              }));
        completer.future.then((SelectableEntity expense) {
          store.dispatch(UpdateCurrentRoute(RecurringExpenseEditScreen.route));
        });
      },
      onCancelPressed: (BuildContext context) {
        createEntity(
            context: context,
            entity: ExpenseEntity(entityType: EntityType.recurringExpense),
            force: true);
        if (state.recurringExpenseUIState.cancelCompleter != null) {
          state.recurringExpenseUIState.cancelCompleter.complete();
        } else {
          store.dispatch(UpdateCurrentRoute(state.uiState.previousRoute));
        }
      },
      onSavePressed: (BuildContext context, [EntityAction action]) {
        Debouncer.runOnComplete(() {
          final recurringExpense = store.state.recurringExpenseUIState.editing;
          final localization = AppLocalization.of(context);
          if (recurringExpense.isOld &&
              recurringExpense.isChanged == false &&
              action != null &&
              action.isClientSide) {
            handleEntityAction(recurringExpense, action);
          } else {
            final Completer<ExpenseEntity> completer =
                new Completer<ExpenseEntity>();
            store.dispatch(SaveRecurringExpenseRequest(
              completer: completer,
              recurringExpense: recurringExpense,
              action: action,
            ));
            return completer.future.then((savedRecurringExpense) {
              showToast(recurringExpense.isNew
                  ? localization.createdRecurringExpense
                  : localization.updatedRecurringExpense);
              if (state.prefState.isMobile) {
                store.dispatch(
                    UpdateCurrentRoute(RecurringExpenseViewScreen.route));
                if (recurringExpense.isNew) {
                  Navigator.of(context)
                      .pushReplacementNamed(RecurringExpenseViewScreen.route);
                } else {
                  Navigator.of(context).pop(savedRecurringExpense);
                }
              } else {
                if (!state.prefState.isPreviewVisible) {
                  store.dispatch(TogglePreviewSidebar());
                }

                viewEntity(entity: savedRecurringExpense);

                if (state.prefState.isEditorFullScreen(EntityType.expense) &&
                    state.prefState.editAfterSaving) {
                  editEntity(entity: savedRecurringExpense);
                }
              }

              if (action != null && action.isClientSide) {
                handleEntityAction(savedRecurringExpense, action);
              } else if (action != null && action.requiresSecondRequest) {
                handleEntityAction(savedRecurringExpense, action);
                viewEntity(entity: savedRecurringExpense, force: true);
              }
            }).catchError((Object error) {
              showDialog<ErrorDialog>(
                  context: context,
                  builder: (BuildContext context) {
                    return ErrorDialog(error);
                  });
            });
          }
        });
      },
      onUploadDocument: (BuildContext context, MultipartFile multipartFile) {
        final Completer<DocumentEntity> completer = Completer<DocumentEntity>();
        store.dispatch(SaveRecurringExpenseDocumentRequest(
            multipartFile: multipartFile,
            expense: recurringExpense,
            completer: completer));
        completer.future.then((client) {
          showToast(AppLocalization.of(context).uploadedDocument);
        }).catchError((Object error) {
          showDialog<ErrorDialog>(
              context: context,
              builder: (BuildContext context) {
                return ErrorDialog(error);
              });
        });
      },
      onDeleteDocument: (BuildContext context, DocumentEntity document,
          String password, String idToken) {
        final completer = snackBarCompleter<Null>(
            context, AppLocalization.of(context).deletedDocument);
        completer.future.then<Null>((value) => store.dispatch(
            LoadRecurringExpense(recurringExpenseId: recurringExpense.id)));
        store.dispatch(DeleteDocumentRequest(
          completer: completer,
          documentIds: [document.id],
          password: password,
          idToken: idToken,
        ));
      },
    );
  }
}
