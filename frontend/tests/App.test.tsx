import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it } from "vitest";
import App from "../src/App";
import { setupApi } from "./fixtures";

it("selects an actor through the session endpoint and signs out", async () => {
  const mock = setupApi("created", false, false);
  render(<App />);
  await userEvent.click(await screen.findByRole("button", { name: "Alex" }));
  expect(await screen.findByRole("table", { name: "Orders" })).toBeInTheDocument();
  const selection = mock.fetchMock.mock.calls.find(([url, options]) => url === "/v1/session" && options?.method === "POST")!;
  expect(JSON.parse(selection[1]?.body as string)).toEqual({ actor_id: 1 });
  expect(selection[1]?.credentials).toBe("same-origin");
  await userEvent.click(screen.getByRole("button", { name: "Switch participant" }));
  expect(await screen.findByRole("button", { name: "Alex" })).toBeInTheDocument();
  expect(screen.queryByRole("table", { name: "Orders" })).not.toBeInTheDocument();
});
it("restores the existing cookie session on reload", async () => {
  const mock = setupApi();
  render(<App />);
  await screen.findByRole("table", { name: "Orders" });
  await waitFor(() => expect(mock.fetchMock.mock.calls.some(([url, options]) => url === "/v1/session" && options?.method === "POST")).toBe(false));
});
