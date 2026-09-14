import { render, screen, within, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import Dashboard from '../src/OrdersDashboard'
import { setupApi as api } from './fixtures'
async function orderRow() {
  const table = await screen.findByRole('table', { name: 'Orders' })
  return within(table).findByRole('row', { name: /#42/ })
}

function expectMutation(fetchMock: ReturnType<typeof vi.fn>, path: string) {
  const mutations = fetchMock.mock.calls.filter(([input, options]) =>
    (options?.method ?? (input instanceof Request ? input.method : 'GET')) === 'POST')
  expect(mutations).toHaveLength(1)
  const [input] = mutations[0]
  const url = new URL(input instanceof Request ? input.url : String(input), 'http://localhost')
  expect(url.pathname).toBe(path)
}

describe('OrdersDashboard', () => {
  it('shows the order and its current status in the orders table', async () => {
    api()
    render(<Dashboard actorId={1} />)
    const row = await orderRow()
    expect(row).toHaveTextContent('created')
    expect(row).toHaveTextContent('2.50')
  })

  it('offers Complete and Cancel for a created order', async () => {
    api()
    render(<Dashboard actorId={1} />)
    const row = within(await orderRow())
    expect(row.getByRole('button', { name: 'Complete' })).toBeEnabled()
    expect(row.getByRole('button', { name: 'Cancel' })).toBeEnabled()
  })

  it('offers only Cancel for a successful order', async () => {
    api('successful')
    render(<Dashboard actorId={1} />)
    const row = within(await orderRow())
    expect(row.queryByRole('button', { name: 'Complete' })).not.toBeInTheDocument()
    expect(row.getByRole('button', { name: 'Cancel' })).toBeEnabled()
  })

  it('offers no mutation buttons for a cancelled order', async () => {
    api('cancelled')
    render(<Dashboard actorId={1} />)
    expect(within(await orderRow()).queryAllByRole('button')).toHaveLength(0)
  })

  it('completes through the correct endpoint and refreshes balance, status and transactions', async () => {
    const { fetchMock } = api()
    const user = userEvent.setup()
    render(<Dashboard actorId={1} />)
    await user.click(within(await orderRow()).getByRole('button', { name: 'Complete' }))
    await waitFor(() => expect(screen.getByLabelText('Balance')).toHaveTextContent('7.50'))
    await waitFor(async () => expect(await orderRow()).toHaveTextContent('successful'))
    expect(await within(await screen.findByRole('table', { name: 'Transactions' })).findByText('charge')).toBeInTheDocument()
    expectMutation(fetchMock, '/v1/orders/42/complete')
  })

  it('cancels through the correct endpoint and shows the refund and reversal', async () => {
    const { fetchMock } = api('successful')
    const user = userEvent.setup()
    render(<Dashboard actorId={1} />)
    await user.click(within(await orderRow()).getByRole('button', { name: 'Cancel' }))
    await waitFor(() => expect(screen.getByLabelText('Balance')).toHaveTextContent('10.00'))
    await waitFor(async () => expect(await orderRow()).toHaveTextContent('cancelled'))
    const journal = within(await screen.findByRole('table', { name: 'Transactions' }))
    expect(await journal.findByText('reversal')).toBeInTheDocument()
    expect(journal.getByText('charge')).toBeInTheDocument()
    expectMutation(fetchMock, '/v1/orders/42/cancel')
  })

  it.each(['Complete', 'Cancel'])('disables %s while its mutation is pending', async (action) => {
    const mock = api()
    let release!: (value: Response) => void
    mock.setMutation(() => new Promise<Response>((resolve) => { release = resolve }))
    const user = userEvent.setup()
    render(<Dashboard actorId={1} />)
    const button = within(await orderRow()).getByRole('button', { name: action })
    await user.click(button)
    try {
      await waitFor(() => expect(button).toBeDisabled())
      await user.click(button)
      expectMutation(mock.fetchMock, `/v1/orders/42/${action.toLowerCase()}`)
    } finally {
      release(mock.json({ error: { code: 'insufficient_funds', message: 'Insufficient funds' } }, 422))
    }
    await screen.findByRole('alert')
    expect(button).toBeEnabled()
  })

  it('shows insufficient funds and keeps the balance, status and journal unchanged', async () => {
    const mock = api()
    mock.setMutation(async () => mock.json({ error: { code: 'insufficient_funds', message: 'Insufficient funds' } }, 422))
    const user = userEvent.setup()
    render(<Dashboard actorId={1} />)
    await user.click(within(await orderRow()).getByRole('button', { name: 'Complete' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Insufficient funds')
    expect(await orderRow()).toHaveTextContent('created')
    expect(screen.getByLabelText('Balance')).toHaveTextContent('10.00')
    const journal = within(screen.getByRole('table', { name: 'Transactions' }))
    expect(journal.queryByText('charge')).not.toBeInTheDocument()
    expect(journal.queryByText('reversal')).not.toBeInTheDocument()
    expect(within(await orderRow()).getByRole('button', { name: 'Complete' })).toBeEnabled()
  })
})


it('shows incoming payments for a seller without buyer actions', async () => {
  api('successful', true)
  render(<Dashboard actorId={1} />)
  const row = await orderRow()
  expect(within(row).queryAllByRole('button')).toHaveLength(0)
  expect(row).toHaveTextContent('Sale')
  const journal = within(screen.getByRole('table', { name: 'Transactions' }))
  expect(journal.getByText('+$2.50')).toBeInTheDocument()
})

it('shows opening funds without an order and exposes both entries', async () => {
  const mock = api()
  mock.transactions.push({ id: 80, order_id: null, kind: 'opening_balance', reversal_of_id: null,
    entries: [
      { id: 1, account_id: 7, actor_id: 1, amount_minor: 1000, currency: 'USD', direction: 'credit' },
      { id: 2, account_id: 9, actor_id: 3, amount_minor: 1000, currency: 'USD', direction: 'debit' },
    ],
  })
  render(<Dashboard actorId={1} />)
  const journal = within(await screen.findByRole('table', { name: 'Transactions' }))
  expect(journal.getByText('+$10.00')).toBeInTheDocument()
  expect(journal.queryByText('#null')).not.toBeInTheDocument()
  await userEvent.click(journal.getByText('TX-80'))
  const entries = within(journal.getByRole('list', { name: 'Entries for TX-80' }))
  expect(entries.getByText('debit')).toBeInTheDocument()
  expect(entries.getByText('credit')).toBeInTheDocument()
})

it('creates an order with a selected seller and exact minor units', async () => {
  const mock = api()
  render(<Dashboard actorId={1} />)
  await orderRow()
  const user = userEvent.setup()
  await user.click(screen.getByRole('button', { name: 'New order' }))
  await user.selectOptions(screen.getByRole('combobox', { name: 'Seller' }), '2')
  await user.type(screen.getByLabelText('Amount (USD)'), '0.29')
  await user.click(screen.getByRole('button', { name: 'Create order' }))
  expect(await screen.findByText('#43')).toBeInTheDocument()
  const call = mock.fetchMock.mock.calls.find(([url, options]) => String(url) === '/v1/actors/1/orders' && options?.method === 'POST')!
  expect(JSON.parse(call[1]?.body as string)).toEqual({ order: { seller_id: 2, amount_minor: 29, currency: 'USD' } })
  expect(screen.getByLabelText('Balance')).toHaveTextContent('10.00')
})

it('retains a successful payment when the subsequent journal refresh fails', async () => {
  const mock = api()
  render(<Dashboard actorId={1} />)
  const row = await orderRow()
  mock.failJournal()
  await userEvent.click(within(row).getByRole('button', { name: 'Complete' }))
  expect(await screen.findByRole('alert')).toHaveTextContent('Order saved')
  expect(screen.getByLabelText('Balance')).toHaveTextContent('7.50')
  expect(await orderRow()).toHaveTextContent('successful')
})

it('ignores the initial response after a newer refresh has completed', async () => {
  const { httpApi } = await import('../src/api');
  const mock = api();
  const initial = await httpApi.load(1);
  let resolveInitial!: (value: typeof initial) => void;
  const load = vi.fn().mockImplementationOnce(() => new Promise((resolve) => { resolveInitial = resolve; }))
    .mockResolvedValueOnce(initial);
  const customApi = { ...httpApi, load };
  render(<Dashboard actorId={1} api={customApi} />);
  await userEvent.click(screen.getByRole('button', { name: 'Refresh' }));
  await userEvent.click(within(await orderRow()).getByRole('button', { name: 'Complete' }));
  await waitFor(() => expect(screen.getByLabelText('Balance')).toHaveTextContent('7.50'));
  await waitFor(() => expect(mock.fetchMock.mock.calls.some(([url]) => String(url).includes('/complete'))).toBe(true));
  const { act } = await import('@testing-library/react');
  await act(async () => { resolveInitial(initial); });
  expect(screen.getByLabelText('Balance')).toHaveTextContent('7.50');
  expect(await orderRow()).toHaveTextContent('successful');
});
